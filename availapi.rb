#!/usr/bin/env ruby

require 'rubygems'
require 'builder'
require 'hpricot'
require 'json'
require 'open-uri'
require 'rack/conneg'
require 'sinatra'
require 'preprocessor'
require 'yaml'

API_VERSION = '0.1.3'

use(Rack::Preprocessor) { |env|
  # Remove 's.' prefixes from parameters; force params['id'] to be an array type
  env['QUERY_STRING'] = env['QUERY_STRING'].gsub(/\bs\./,'').gsub(/\bid=/,'id[]=')
}

use(Rack::Conneg) { |conneg|
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.provide([:json, :xml])
}

configure do
  config_file = File.join(File.dirname(__FILE__), 'config/config.yml')
  opts = YAML.load(File.read(config_file))
  set opts
end

before do
  puts request.params.inspect
  content_type negotiated_type
end

helpers do

  def get_availabilities(bibs)
    start_time = Time.now
    result = { 'version' => API_VERSION, 'availabilityItems' => [] }
    bibs.each { |bib|
      result['availabilityItems'] << get_availability(bib)
    }
    result['totalRequestTime'] = (Time.now - start_time).round
    return result
  end

  def get_availability(bib)
    availability_regexp = Regexp.compile(options.availability_test[:regexp])
    result = { 'id' => bib, 'availabilities' => [] }
    uri = options.opac_uri % bib
    page = Hpricot(open(uri))
    page.search(options.item_container).each do |item|
      data = item.children.collect { |c| 
        t = c.inner_text
        if options.process_entry
          t.gsub!(*(options.process_entry))
        end
        t.strip
      }
      data.reject! { |t| t.empty? }
      location = data.first
      status = data.last
      availability = {
        'status' => availability_regexp === (options.availability_test[:source] % data) ? 'available' : 'unavailable'
      }
      options.result_fields.each_pair { |key,format|
        availability[key] = format % data
      }
      result['availabilities'] << availability
    end
    return result
  end

end

get '/availability' do
  data = get_availabilities(params['id'] || [])
  
  respond_to do |wants|
    wants.xml {
      xml = Builder::XmlMarkup.new
      xml.response(:version => data['version'], :totalRequestTime => data['totalRequestTime']) do
        xml.availabilityItems do
          data['availabilityItems'].each { |item|
            xml.availabilities(:id => item['id']) do
              item['availabilities'].each { |avail|
                xml.availability(avail)
              }
            end
          }
        end
      end
      xml.target!
    }
    wants.json  { data.to_json }
    wants.other { content_type 'text/plain'; error 400, 'Bad Request' }
  end
  
end
