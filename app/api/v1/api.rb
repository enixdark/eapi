require 'active_support'

module V1
  class API < Grape::API
    version 'v1', using: :header, vendor: 'v1'
    format :json
    prefix :api

    before do
      header "Access-Control-Allow-Origin", "*"
    end

    # List regex to extract some data from message or mail context
    REGEX_EMAIL = /([\w+\-]\.?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+/i
    REGEX_FROM_EMAIL =  /from=<#{REGEX_EMAIL}>/i
    REGEX_TO_EMAIL =  /to=<#{REGEX_EMAIL}>/i
    REGEX_TIME = /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\d\s]+:\d{2}:\d{2}/i
    REGEX_STATUS = /status=\w+/i
    REGEX_ERROR_MESSAGE = /sender address rejected[\w\W]+\)/i
    REGEX_SUBJECT = /subject:[\w\s]+from/i
    NUMBER_ON_PAGE = 25
    NUMBER_MAX_PAGE = 10000

    REGEX_SMTP_RESPONSE = /said:\s+\d{1,3}[\-\s]+\d{1,3}.\d{1,3}.\d{1,3}/i
    REGEX_AUTHEN_INVALID = /authentication failure: client response/i

    # extract and format some field from json message
    def self.extract_message(item)
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

    def self.compare_time(time1, time2, symbol)
      tp = DateTime.parse(time1) #.strftime('%Q')
      ti = DateTime.parse(time2)
      symbol == :to ? tp <= ti : tp >= ti
    end

    def self.extract_code(item)
      message = item["message"]
      email = REGEX_EMAIL.match(message)[0] rescue nil
      timestamp =  DateTime.parse(item["@timestamp"]).strftime("%Y-%m-%d %H:%M:%S") rescue nil
      code = REGEX_SMTP_RESPONSE.match(message)[0].split(/[\-\s]/)[1].to_i rescue nil
      status = REGEX_STATUS.match(message)[0].split("=")[1] rescue nil
      unless code
        code = REGEX_AUTHEN_INVALID.match(message) == nil ? nil : 535
      end
      {
        email: email,
        timestamp: timestamp,
        code: code,
        status: status
      }
    end

    def self.response(params, size, *args)
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
      query = must.flatten.empty? ? { query: { match_all: {} } } : { query: { bool: { must: must } } }
      response = Elasticsearch::Model.client.search index: 'logstash-*',
        body: query.merge( { from: (page - 1)*size, size: size })
      [response["hits"]["hits"].map { |item| item["_source"] }
                              .map { |item| yield(item) }, page]
    end


    resource :statistic do
      desc 'Return statistic messages of email'
      params do
        optional :email, type: String
        optional :from, type: String
        optional :to, type: String
        optional :page, type: Integer
        optional :status, type: String
      end

      get do
        (response,page) = API.response(params, NUMBER_MAX_PAGE, :email, :status) { |item| API.extract_code(item) }
        records = response.select { |item| item[:code] != nil && ( params.key?(:email) ? params[:email] == item[:email] : true ) }
                          # .inject({}) do |dict, item|
                          #   unless dict.key? item[:code]
                          #      dict[item[:code]] = 1
                          #   else
                          #      dict[item[:code]] += 1
                          #   end
                          #   dict
                          # end
        records
      end


    end


    resource :messages do
      desc 'Return result messages'
      params do
        optional :from_email, type: String
        optional :to_email, type: String
        optional :status, type: String
        optional :from, type: String
        optional :to, type: String
        optional :page, type: Integer
      end
      get do
        (response,page) = API.response(params, NUMBER_ON_PAGE, :from_email, :to_email, :status) { |item| API.extract_message(item) }
         records       = response.select do |item| params.slice(:from_email, :to_email, :to,:from,:status).keys.map do |it| (
                           it.to_sym != :to && it.to_sym != :from ? ( params[it] == item[it.to_sym] )
                           : API.compare_time(item[:timestamp],params[it], it.to_sym) ) end.all?
                         end

        # return json data
        {
        _meta: {
        total_records: records.length,
        page_size: nil,
        page: page,
        page_count: nil,
        records: records
                }
        }
      end
    end


  end
end

