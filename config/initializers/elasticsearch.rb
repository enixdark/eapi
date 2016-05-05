config = {
  host: RAILS.ENV["ELASTICSEARCH_HOST"],
  #host: 'http://localhost:9200',
  transport_options: {
    request: { timeout: 5 }
  },
}

#if File.exists?("config/elasticsearch.yml")
#  config.merge!(YAML.load_file("config/elasticsearch.yml").symbolize_keys)
#end

Elasticsearch::Model.client = Elasticsearch::Client.new(config)
