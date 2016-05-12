 require_relative 'cache'
 module Helper
 	# List regex to extract some data from message or mail context
    REGEX_EMAIL = /([\w+\-]\.?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+/i
    REGEX_FROM_EMAIL =  /header\sfrom:\s#{REGEX_EMAIL}/i # /from=<#{REGEX_EMAIL}>/i
    REGEX_TO_EMAIL =   /header\sto:\s#{REGEX_EMAIL}/i # /to=<#{REGEX_EMAIL}>/i
    REGEX_TIME = /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\d\s]+:\d{2}:\d{2}/i
    REGEX_STATUS = /status=\w+/i
    # REGEX_ERROR_MESSAGE = /sender address rejected[\w\W]+\)/i
    REGEX_ERROR_MESSAGE = /said:\s[\w\W]+\)/i
    REGEX_SUBJECT = /subject:[\w\s]+(,|from)/i
    NUMBER_ON_PAGE = 25
    NUMBER_MAX_PAGE = 10000

    REGEX_SMTP_RESPONSE = /(said:\s+|\()\d{1,3}([\-\s]+\d{1,3}.\d{1,3}.\d{1,3}|\s[\w])+/i
    REGEX_AUTHEN_INVALID = /authentication failure: client response/i

    REGEX_ID = /postfix\/[\w\[\]:]+:(\s\w+:)?\s[\w\d]+:/i

    INDEX = 'logstash-*'


    # extract and format some field from json message
    def extract_message(item)
      # message = item["message"]
      # timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
      # from = REGEX_EMAIL.match(REGEX_FROM_EMAIL.match(message)[0])[0] rescue nil
      # to = REGEX_EMAIL.match(REGEX_TO_EMAIL.match(message)[0])[0] rescue nil
      # status = REGEX_STATUS.match(message)[0].split("=")[1] rescue nil
      # subject = REGEX_SUBJECT.match(message)[0].split(" ")[1..-2].join(" ") rescue nil
      # error_message = ( status == "deferred" || status == "bounced" ) ? ( REGEX_ERROR_MESSAGE.match(message)[0] rescue nil )  : nil
      { :timestamp =>  item[:timestamp],
        :status => item[:status],
        :from => item[:from] ,
        :to => item[:to] ,
        :subject => item[:subject],
      }.merge( item[:error_message] ? { error_message: item[:error_message].split(" ")[1..-1].join(" ") } : {})
    end


    def extract_code(item, _subject = false)
      message = item[:error_message]
      # email = REGEX_EMAIL.match(message)[0] rescue nil
      # timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil

      # status = REGEX_STATUS.match(message)[0].split("=")[1] rescue 
	    status = item[:status]
	    if status == "sent"
	  	  code = 250
	    else
	  	  check_code = REGEX_SMTP_RESPONSE.match(message)[0].split(/[\-\s]/)[1].to_i rescue nil
	  	  if check_code && check_code.to_i != 0
	        code = check_code
	  	  else
	  	    case message
	  	      when /Host or domain name not found/
	  	  	    code = 512
	  	      else
	  	  	    code = nil
	  	    end
	  	  end
	    end
	    if _subject
	  	  subject = item[:error_message].split(" ")[1..-1].join(" ") rescue nil  # REGEX_ERROR_MESSAGE.match(message)[0].split(" ")[1..-1].join(" ") rescue nil
	    end
      {
    	  email: item[:from],
    	  to: item[:to],
        timestamp: item[:timestamp],
        code: code,
        status: status,
      }.merge( _subject ? {subject: subject } : {} )
    end

    def ids(params)
    	from = params.key?(:from) ? DateTime.parse("#{params[:from]} 00:00:00").strftime('%Q').to_i : nil
      to = params.key?(:to) ? DateTime.parse("#{params[:to]} 23:59:59").strftime('%Q').to_i : nil
      must = [[]]
      	must[0].push(*[{ range: { "@timestamp": {}.merge(gte: from).merge(lte: to).select { |key,value| value != nil } } }
      ])
      response = Elasticsearch::Model.client.search index: INDEX,
        body: { _source: false, query: { bool: { must: must } } ,aggs: { ids: { terms: { field: "qid.raw", size: 0}}} ,  sort: [{"@timestamp": "asc" }] }
      response["aggregations"]["ids"]["buckets"].map { |item| item["key"] }
    end

    def response(params, size, *args)
      _ids = ids(params)
      page = params.key?(:page) ? params[:page].to_i : 1
      [(_ids[(page-1)*size..page*size] || [])
      .map { |item|
            response_with_id(params, item) { |item| yield(item) }
      }, page ]
    end

    def response_with_id(params, id ,  *args)
      
      unless Cache::Data.key? id
      	from = params.key?(:from) ? DateTime.parse("#{params[:from]} 00:00:00").strftime('%Q').to_i : nil
      	to = params.key?(:to) ? DateTime.parse("#{params[:to]} 23:59:59").strftime('%Q').to_i : nil
      	must = [[]]
      	must[0].push(*[{ range: { "@timestamp": {}.merge(gte: from).merge(lte: to).select { |key,value| value != nil } } },
      		{ match: { message: id }}
      	])
        response = Elasticsearch::Model.client.search index: INDEX, 
          body: { query: { bool: { must: must } } }.merge({ from:0, size:50, sort: [{"@timestamp": "asc" }] })
        response = response["hits"]["hits"]
        from = response.map { |item| item["_source"]["from"] }.uniq.compact.pop# (response.map { |item| REGEX_EMAIL.match(REGEX_FROM_EMAIL.match(item["_source"]["message"])[0])[0] rescue nil }).uniq.compact.pop
        to = response.map { |item| item["_source"]["to"] }.uniq.compact.pop # (response.map { |item| REGEX_EMAIL.match(REGEX_TO_EMAIL.match(item["_source"]["message"])[0])[0] rescue nil }).uniq.compact.pop
        message = response.map { |item| item["_source"]["message"] }.join("\n") rescue nil
        status = response.map { |item| item["_source"]["result"] }.uniq.compact.pop
        timestamp = DateTime.parse(response[0]["_source"]["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
        error_message = (response.map { |item| REGEX_ERROR_MESSAGE.match(item["_source"]["message"])[0] rescue nil }).uniq.compact.pop
        subject = response.map { |item| REGEX_SUBJECT.match(item["_source"]["message"])[0].split(" ")[1..-2].join(" ") rescue nil }.compact.pop
        reason = response.map { |item| item["_source"]["reason"] }.compact.pop
        Cache::Data.put(id, { message: message, timestamp: timestamp, id: id, status: status, to: to, from: from,
         subject: subject, reason: reason, error_message: error_message })
      end

      response = Cache::Data.get(id)
      yield(response)
    end
 end