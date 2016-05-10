 module Helper
 	# List regex to extract some data from message or mail context
    REGEX_EMAIL = /([\w+\-]\.?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+/i
    REGEX_FROM_EMAIL =  /from=<#{REGEX_EMAIL}>/i
    REGEX_TO_EMAIL =  /to=<#{REGEX_EMAIL}>/i
    REGEX_TIME = /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\d\s]+:\d{2}:\d{2}/i
    REGEX_STATUS = /status=\w+/i
    # REGEX_ERROR_MESSAGE = /sender address rejected[\w\W]+\)/i
    REGEX_ERROR_MESSAGE = /said:\s[\w\W]+\)/i
    REGEX_SUBJECT = /subject:[\w\s]+from/i
    NUMBER_ON_PAGE = 25
    NUMBER_MAX_PAGE = 10000

    REGEX_SMTP_RESPONSE = /(said:\s+|\()\d{1,3}([\-\s]+\d{1,3}.\d{1,3}.\d{1,3}|\s[\w])+/i
    REGEX_AUTHEN_INVALID = /authentication failure: client response/i

    INDEX = 'logstash-*'

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
      error_message = status == "deferred" ? ( REGEX_ERROR_MESSAGE.match(message)[0] rescue nil )  : nil
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
      message = item["message"]
      email = REGEX_EMAIL.match(message)[0] rescue nil
      timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
      status = REGEX_STATUS.match(message)[0].split("=")[1] rescue nil
      code = status == "sent" ? 250 : REGEX_SMTP_RESPONSE.match(message)[0].split(/[\-\s]/)[1].to_i rescue nil
      if _subject
      	subject = REGEX_ERROR_MESSAGE.match(message)[0].split(" ")[1..-1].join(" ") rescue nil
      end
      # unless code
      #   code = REGEX_AUTHEN_INVALID.match(message) == nil ? nil : 535
      #
      {
        email: email,
        timestamp: timestamp,
        code: code,
        status: status
      }.merge( _subject ? {subject: subject} : {} )
    end


    def response_with_filter(params, size, filter, *args)
      page = params.key?(:page) ? params[:page].to_i : 1
      must = [] << {}.merge(params.slice(args)).values.map do |item|
        {
          match: {
              message: item
          }
        }
      end
      from = params.key?(:from) ? DateTime.parse("#{params[:from]} 00:00:00").strftime('%Q').to_i : nil
      to = params.key?(:to) ? DateTime.parse("#{params[:to]} 23:59:59").strftime('%Q').to_i : nil
      must[0] << { range: { "@timestamp": {}.merge(gte: from).merge(lte: to).select { |key,value| value != nil } } }
      must[0] << { match: { message: "postfix/smtp" } }
      query = must.flatten.empty? ? { query: { match_all: {} } } :
       { query: { bool: { must: must, filter: filter } } }
      response = Elasticsearch::Model.client.search index: INDEX,
        body: query.merge( { from: (page - 1)*size, size: size })
      [response["hits"]["hits"].map { |item| item["_source"] }
                              .map { |item| yield(item) }, page]
    end

    def response(params, size, *args)
      self.response_with_filter(params, size,
      	{ bool: { should: [{ match: { message: "said:" } }, { match: { message: "status=" } } ] } }, args) { |item| yield(item) }
    end

 end