require 'builder'
require 'json'
require 'ostruct'
begin
  require 'memcache'
rescue LoadError
  # Continue without caching
end

class Hash
  def stringify
    inject({}) { |m,(k,v)|
      m[k.to_s] = v.respond_to?(:stringify) ? v.stringify : v
      m
    }
  end
end

class AvailabilityHash

  API_VERSION = '0.1.8' unless defined?(API_VERSION)
  
  def initialize(attributes = {})
    @hash = { 'version' => API_VERSION, 'availabilityItems' => [] }.merge(attributes)
  end

  def to_json
    @hash.to_json
  end
  
  def to_jsons
    result = @hash['availabilityItems'].inject(StringIO.new('')) { |strio,item| strio.puts(item.to_json); strio }
    result.string
  end
  
  def to_xml
    xml = Builder::XmlMarkup.new
    response_attrs = @hash.reject { |k,v| v.is_a?(Array) or v.is_a?(Hash) }
    response_attrs['xmlns:xlink'] = 'http://www.w3.org/1999/xlink'
    xml.response(response_attrs) do
      xml.availabilityItems do
        @hash['availabilityItems'].each { |item|
          attrs = { :id => item['id'], :bib => item['bib'] }
          if item['expires']
            attrs[:expires] = item['expires'].xmlschema
          end
          xml.availabilities(attrs) do
            item['availabilities'].each { |avail|
              attrs = avail.dup
              if attrs['href']
                attrs['xlink:href'] = attrs.delete('href')
                attrs['xlink:title'] = attrs.delete('link_text')
                attrs['xlink:type'] = 'locator'
              end
              attrs.reject! { |k,v| v.nil? }
              xml.availability(attrs)
            }
          end
        }
      end
    end
    xml.target!
  end
  
  def method_missing(sym, *args)
    if @hash.respond_to?(sym)
      @hash.send(sym, *args)
    else
      super(sym, *args)
    end
  end

end

# Subclass of Hash that lets us uniq-ify based on key/value pairs
class ContentAwareHash < Hash
  def hash
    values.inject(0) { |acc,value| acc + value.hash }
  end

  def eql?(a_hash)
    self == a_hash
  end
end

class AvailabilityScraper
  attr :cache
  attr :default_ttl
  attr :short_ttl
  
  def initialize(config = {})
    unless config[:cache].nil? or not defined?(MemCache)
      @default_ttl = config[:cache][:default_ttl] || 1800
      @short_ttl = config[:cache][:short_ttl] || 300
      @cache = MemCache.new(config[:cache][:server], :namespace => self.class.name)
    end
  end
  
  def get_availabilities(bibs)
    start_time = Time.now
    result = ::AvailabilityHash.new('scraperClass' => self.class.name)
    bibs.each { |bib|
      fname = File.join(File.dirname(__FILE__), "../../test/#{bib}.yml")
      if File.exists?(fname)
        result['availabilityItems'] << YAML.load(File.read(fname))
      else
        result['availabilityItems'] << get_cached_availability(bib)
      end
    }
    result['totalRequestTime'] = (Time.now - start_time).round
    return result
  end

  def get_availability(bib)
    { 'id' => bib, 'availabilities' => [] }
  end
  
  private
  def get_cached_availability(bib)
    if cache.nil?
      get_availability(bib)
    else
      begin
        result = cache.get(bib)
        if result.nil?
          result = get_availability(bib)
          ttl = begin
            result.delete('ttl') || @default_ttl
          rescue
            @default_ttl
          end
          result['expires'] = Time.now + ttl
          cache.add(bib, result, ttl)
        end
      rescue MemCache::MemCacheError
        result = get_availability(bib)
      end
      return result
    end
  end
  
end
