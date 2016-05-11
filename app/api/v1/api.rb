require 'active_support'
require_relative 'helper'
module V1
  class API < Grape::API
    extend Helper
    version 'v1', using: :header, vendor: 'v1'
    format :json
    prefix :api

    before do
      header "Access-Control-Allow-Origin", "*"
    end

    resource :ids do
      desc 'Return statistic messages of email'
      params do
        optional :email, type: String
        optional :from, type: String
        optional :to, type: String
        optional :page, type: Integer
        optional :status, type: String
      end

      get do
        # the previous api to get all ids through bool query with must/should/filter
        # (response,page) = API::response(params, Helper::NUMBER_MAX_PAGE, :email) { |item| API::extract_id(item) }
        # response.uniq.compact
        
        # the current query use aggs
        ids = API::ids
      end
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
        # API.endpoints[0].call(env)
        # (response,page) = API::response(params, Helper::NUMBER_MAX_PAGE, :email) { |item| API::extract_code(item) }
        # records = response.select { |item| (item[:code] != nil || params[:status] != nil) &&
        #   ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
        #   ( params.key?(:status) ? params[:status] == item[:status] : true )
        # }
        #   .inject({}) do |dict, item|
        #     dict[item[:code]] = dict.key?(item[:code]) ? (dict[item[:code]]  + 1) : 1
        #     dict
        #   end
        # records
        ids = API::ids
        page = params.key?(:page) ? params[:page].to_i : 1
        records = (ids[(page-1)*Helper::NUMBER_ON_PAGE..page*Helper::NUMBER_ON_PAGE] || [])
          .map { |item|
            API::response_with_id(params, item) { |item| API::extract_code(item) }
          }
          .select do |item| params.slice(:from_email, :to_email, :status).keys.map do |it|
               params[it] == item[it.split('_')[0].to_sym]
             end.all?
           end
           .inject({}) do |dict, item|
            dict[item[:code]] = dict.key?(item[:code]) ? (dict[item[:code]]  + 1) : 1
            dict
          end
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
        ids = API::ids
        page = params.key?(:page) ? params[:page].to_i : 1
        records = (ids[(page-1)*Helper::NUMBER_ON_PAGE..page*Helper::NUMBER_ON_PAGE] || []) 
          .map { |item|
            API::response_with_id(params, item) { |item| API::extract_message(item) }
          }
          .select do |item| params.slice(:from_email, :to_email, :status).keys.map do |it|
               params[it] == item[it.split('_')[0].to_sym]
             end.all?
           end

        # (response,page) = API::response(params, Helper::NUMBER_ON_PAGE, :from_email, :to_email) { |item| API::extract_message(item) }
        #  records       = response
        #                  .select do |item| params.slice(:from_email, :to_email).keys.map do |it|
        #                      params[it] == item[it.split('_')[0].to_sym]
        #                    end.all?
        #                  end

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


      desc 'Return list error messages that server response'
      params  do
        optional :email, type: String
        optional :status, type: String
        optional :from, type: String
        optional :to, type: String
        optional :page, type: Integer
      end
      get :server_error do
        # (response,page) = API::response_with_filter(params, Helper::NUMBER_ON_PAGE,
        #   [{ match: { message: "said:" } },{ match_phrase: { message: "postfix/smtp" } }, { regexp: { message: "(500|501|502|503|504|510|511|512|513|523|530|541|550|551|552|553|554)" } }],
        #   [],
        #   {},
        #   :email, :status) { |item| API::extract_code(item,true) }
        # records = response
        # filter { bool: { must: [{ match: { message: "said:" } }, { regexp: { message: "(500|501|502|503|504|510|511|512|513|523|530|541|550|551|552|553|554)" } }] } }
        #.select { |item| ( item[:code].to_i >= 500 ) &&
        #   ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
        #   ( params.key?(:status) ? params[:status] == item[:status] : true )
        # }
        ids = API::ids
        page = params.key?(:page) ? params[:page].to_i : 1
        records = (ids[(page-1)*Helper::NUMBER_ON_PAGE..page*Helper::NUMBER_ON_PAGE] || []) 
          .map { |item|
            API::response_with_id(params, item) { |item| API::extract_message(item) }
          }
          .select { |item| ( item[:code].to_i >= 500 ) &&
          ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
          ( params.key?(:status) ? params[:status] == item[:status] : true )
        }
        records
      end
    end
  end
end

