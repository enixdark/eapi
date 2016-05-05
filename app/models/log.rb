require 'elasticsearch/model'
class Log < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks
end

# Log.__elasticsearch__.client = Elasticsearch::Client.new(config = {
#   host: "http://123.31.11.183:9200/",
#   transport_options: {
#     request: { timeout: 5 }
#   },
# })