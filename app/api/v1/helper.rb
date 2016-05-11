 require_relative 'cache'
 module Helper
 	# List regex to extract some data from message or mail context
    REGEX_EMAIL = /([\w+\-]\.?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+/i
    REGEX_FROM_EMAIL =  /from=<#{REGEX_EMAIL}>/i
    REGEX_TO_EMAIL =  /to=<#{REGEX_EMAIL}>/i
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

    # def extract_id(item)
    #   message = item["message"]
    #   REGEX_ID.match(message)[0].split(":")[-1].strip rescue nil
    # end

    # extract and format some field from json message
    def extract_message(item)
      message = item["message"]
      # timestamp = DateTime.parse("#{DateTime.parse(item['@timestamp']).year} \
      #     #{REGEX_TIME.match(message)[0]}")
      # .strftime("%Y-%m-%d %H:%M:%S") rescue nil
      timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
      from = REGEX_EMAIL.match(REGEX_FROM_EMAIL.match(message)[0])[0] rescue nil
      to = REGEX_EMAIL.match(REGEX_TO_EMAIL.match(message)[0])[0] rescue nil
      status = REGEX_STATUS.match(message)[0].split("=")[1] rescue nil
      subject = REGEX_SUBJECT.match(message)[0].split(" ")[1..-2].join(" ") rescue nil
      error_message = ( status == "deferred" || status == "bounced" ) ? ( REGEX_ERROR_MESSAGE.match(message)[0] rescue nil )  : nil
      { :timestamp =>  timestamp,
        :status => status,
        :from => from ,
        :to => to ,
        :subject => subject
      }.merge( error_message ? { error_message: error_message } : {})
    end

    def compare_time(time1, time2, symbol)
      tp = DateTime.parse(time1) #.strftime('%Q')
      ti = DateTime.parse(time2)
      symbol == :to ? tp <= ti : tp >= ti
    end

    def extract_code(item, _subject = false)
      unless Cache::Code.key? item["id"]
        message = item["message"]
        email = REGEX_EMAIL.match(message)[0] rescue nil
        timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
        status = REGEX_STATUS.match(message)[0].split("=")[1] rescue nil
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
      	  subject = REGEX_ERROR_MESSAGE.match(message)[0].split(" ")[1..-1].join(" ") rescue nil
        end
        Cache::Code.put(id, {
          email: email,
          timestamp: timestamp,
          code: code,
          status: status
        }.merge( _subject ? {subject: subject} : {} ))
      end
      Cache::Code.get item["id"]
    end

    def ids
      response = Elasticsearch::Model.client.search index: INDEX,
        body: { aggs: { ids: { terms: { field: "qid"}}}  , from:0, size:50, sort: [{"@timestamp": "asc" }] }
      response["aggregations"]["ids"]["buckets"].map { |item| item["key"] }
    end

    def response_with_filter(params, size, _must, should, filter, *args)
      page = params.key?(:page) ? params[:page].to_i : 1
      must = [] << {}.merge(params.slice(*args.flatten)).values
                     .map { |item| { match_phrase: { message: item } } }
      #formatter time again
      from = params.key?(:from) ? DateTime.parse("#{params[:from]} 00:00:00").strftime('%Q').to_i : nil
      to = params.key?(:to) ? DateTime.parse("#{params[:to]} 23:59:59").strftime('%Q').to_i : nil

      must[0].push(*[{ range: { "@timestamp": {}.merge(gte: from).merge(lte: to).select { |key,value| value != nil } } },
                    ],
                   *_must
                  )
      if params.key?(:status)
      	must[0] << { match_phrase: { message: "status=#{params[:status]}"} }
      end
      query = must.flatten.empty? ? { query: { match_all: {} } } :
       { query: { bool: { must: must, should: should, filter: filter } } }
      response = Elasticsearch::Model.client.search index: INDEX,
        body: query.merge( { from: (page - 1)*size, size: size , sort: [{"@timestamp": "asc" }]})

      [response["hits"]["hits"].map { |item| item["_source"] }
                              .map { |item| yield(item) }, page]
    end

    def response(params, size, *args)
      self.response_with_filter(params, size, [],
      	[{ match: { message: "said:" }}, { match_phrase: { message: "status="} }, { match_phrase: { message: "postfix/smtp" } }],
      	{} , args) { |item| yield(item) }
        #filter { bool: { should: [{ match: { message: "said:" } }, { match: { message: "status=" } } ] } }
    end

    def response_with_id(params, id ,  *args)
      from = params.key?(:from) ? DateTime.parse("#{params[:from]} 00:00:00").strftime('%Q').to_i : nil
      to = params.key?(:to) ? DateTime.parse("#{params[:to]} 23:59:59").strftime('%Q').to_i : nil
      must = [[]]
      must[0].push(*[{ range: { "@timestamp": {}.merge(gte: from).merge(lte: to).select { |key,value| value != nil } } },
      	             { match: { message: id }}
                    ]
                  )
      unless Cache::Data.key? id
        response = Elasticsearch::Model.client.search index: INDEX, 
          body: { query: { bool: { must: must } } }.merge({ from:0, size:50, sort: [{"@timestamp": "asc" }] })
        Cache::Data.put(id, response["hits"]["hits"])
      end
      response = Cache::Data.get(id)
      message = response.map { |item| item["_source"]["message"] }.join rescue nil
      timestamp = response[0]["_source"]["@timestamp"] rescue nil
      yield({ "message" => message, "@timestamp" => timestamp, id: id})
    end
 end