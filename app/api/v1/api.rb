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
        (response,page) = API::response(params, Helper::NUMBER_MAX_PAGE, :email) { |item| API::extract_code(item) }
        records = response.select { |item| (item[:code] != nil || params[:status] != nil) &&
          ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
          ( params.key?(:status) ? params[:status] == item[:status] : true )
        }
          .inject({}) do |dict, item|
            dict[item[:code]] = dict.key?(item[:code]) ? (dict[item[:code]]  + 1) : 1
            dict
          end
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
        (response,page) = API::response(params, Helper::NUMBER_ON_PAGE, :from_email, :to_email) { |item| API::extract_message(item) }
         records       = response
                         # .select do |item| params.slice(:from_email, :to_email, :to,:from,:status).keys.map do |it| (
                         #   it.to_sym != :to && it.to_sym != :from ? ( params[it] == item[it.to_sym] )
                         #   : API::compare_time(item[:timestamp],params[it], it.to_sym) ) end.all?
                         # end

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
        (response,page) = API::response_with_filter(params, Helper::NUMBER_ON_PAGE,
          [{ match: { message: "said:" } }, { regexp: { message: "(500|501|502|503|504|510|511|512|513|523|530|541|550|551|552|553|554)" } }],
          [],
          {},
          :email, :status) { |item| API::extract_code(item,true) }
        records = response
        # filter { bool: { must: [{ match: { message: "said:" } }, { regexp: { message: "(500|501|502|503|504|510|511|512|513|523|530|541|550|551|552|553|554)" } }] } }
        #.select { |item| ( item[:code].to_i >= 500 ) &&
        #   ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
        #   ( params.key?(:status) ? params[:status] == item[:status] : true )
        # }
        records
      end
    end


  end
end

