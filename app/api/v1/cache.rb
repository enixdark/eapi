module Cache

	
	module Data
	  @data = {}
	  def self.put(key, value)
	  	@data[key] = value
	  end

	  def self.key?(key)
	  	@data.key? key
	  end

	  def self.get(key)
	  	@data[key]
	  end

	  def self.empty?
	  	@data.empty?
	  end

	  def self.data
	  	@data
	  end

	  def self.clean
	  	@data = {}
	  end
	end
end
