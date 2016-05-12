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
        (records, page) = API::response(params, Helper::NUMBER_ON_PAGE) { |item| API::extract_code(item) }
         records = records.select do |item| params.slice(:from_email, :to_email, :status).keys.map do |it|
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

        (records,page) = API::response(params, Helper::NUMBER_ON_PAGE) { |item| API::extract_message(item) }
         records = records.select do |item| params.slice(:from_email, :to_email, :status).keys.map do |it|
                           params[it] == item[it.split('_')[0].to_sym]
                         end.all?
                       end
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
        (records,page) = API::response(params, Helper::NUMBER_ON_PAGE) { |item| API::extract_code(item) }
         records = records.select { |item| ( item[:code].to_i >= 500 ) &&
          ( params.key?(:email) ? params[:email] == item[:email] : true ) &&
          ( params.key?(:status) ? params[:status] == item[:status] : true )
        }
        records
      end
    end
  end
end

