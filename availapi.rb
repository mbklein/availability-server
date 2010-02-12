#!/usr/bin/env ruby

require 'rubygems'
require 'builder'
require 'hpricot'
require 'json'
require 'open-uri'
require 'rack/conneg'
require 'sinatra'
require 'yaml'

VERSION = '0.1.0'

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
  # Force s.id to be an array type
  request.env['QUERY_STRING'] = request.env['QUERY_STRING'].gsub(/s\.id=/,'s.id[]=')
  params['s.id'] = request.params['s.id']
  content_type negotiated_type
end

helpers do

  def get_availabilities(bibs)
    start_time = Time.now
    result = { 'version' => VERSION, 'availabilityItems' => [] }
    bibs.each { |bib|
      result['availabilityItems'] << get_availability(bib)
    }
    result['totalRequestTime'] = (Time.now - start_time).round
    return result
  end

  def get_availability(bib)
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
        'statusMessage'  => options.status_format % data,
        'callNumber'     => options.call_number_format % data,
        'locationString' => options.location_format % data,
        'displayString'  => options.display_format % data
      }
      availability['status'] = options.availability === availability['statusMessage'] ? 'available' : 'unavailable'
      result['availabilities'] << availability
    end
    return result
  end

end

get '/availability' do
  data = get_availabilities(params['s.id'] || [])
  
  respond_to do |wants|
    wants.xml {
      xml = Builder::XmlMarkup.new
      xml.response(:version => data['version'], :totalRequestTime => data['totalRequestTime']) do
        xml.availabilityItems do
          data['availabilityItems'].each { |item|
            xml.availabilities(:id => item['id']) do
              item['availabilities'].each { |avail|
                xml.availability(:displayString => avail['displayString'], :status => avail['status'],
                  :statusMessage => avail['statusMessage'], :locationString => avail['locationString'],
                  :callNumber => avail['callNumber'])
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
