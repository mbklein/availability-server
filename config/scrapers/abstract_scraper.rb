require 'builder'
require 'json'
require 'ostruct'

class AvailabilityHash

  API_VERSION = '0.1.8'
  
  def initialize(attributes = {})
    @hash = { 'version' => API_VERSION, 'availabilityItems' => [] }.merge(attributes)
  end

  def to_json
    @hash.to_json
  end
  
  def to_xml
    xml = Builder::XmlMarkup.new
    response_attrs = @hash.reject { |k,v| v.is_a?(Array) or v.is_a?(Hash) }
    response_attrs['xmlns:xlink'] = 'http://www.w3.org/1999/xlink'
    xml.response(response_attrs) do
      xml.availabilityItems do
        @hash['availabilityItems'].each { |item|
          xml.availabilities(:id => item['id'], :bib => item['bib']) do
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
  attr :options
  
  def get_availabilities(bibs)
    start_time = Time.now
    result = ::AvailabilityHash.new('scraperClass' => self.class.name)
    bibs.each { |bib|
      if bib =~ /^t(.+)$/
        result['availabilityItems'] << YAML.load(File.join(File.dirname(__FILE__), "../../test/#{$1}.yml"))
      else
        result['availabilityItems'] << get_availability(bib)
      end
    }
    result['totalRequestTime'] = (Time.now - start_time).round
    return result
  end

  def get_availability(bib)
    { 'id' => bib, 'availabilities' => [] }
  end
  
end
