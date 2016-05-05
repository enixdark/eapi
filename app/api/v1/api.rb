require 'active_support'

module V1
  class API < Grape::API
    version 'v1', using: :header, vendor: 'v1'
    format :json
    prefix :api

    

    resource :messages do
      desc 'Return result messages'
      params do
        optional :email, type: String
        optional :status, type: String
        optional :timestamp, type: String
        optional :page, type: Integer
      end
      get :filter do
        # response = Elasticsearch::Model.client.perform_request 'POST', 'logstash-*/_search?size=
        shoulds = [] << {}.merge(params.slice(:email, :status, :timestamp)).values.map do |item|
          {
            match: {
                message: item
            }
          }
        end
        response = Elasticsearch::Model.client.search index: 'logstash-*', body: { query: { bool: { should: shoulds } } }

        # Process nlp to extract email , datetime from message
        ## TODO
        #

        # return json data 
        { _meta: {
        total_records: nil,
        page_size: nil,
        page: nil,
        page_count: 5,
        records: response.body["hits"]["hits"].map { |item| item["_source"] }
                                              .map { |item| { :timestamp => nil ,
                                                              :status => nil,
                                                              :from => nil ,
                                                              :to => nil ,
                                                              :error_message => nil ,
                                                              :subject => nil
                        }
                }
        }
      end
    end
  end
end