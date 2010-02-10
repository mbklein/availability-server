#!/usr/bin/env ruby

require 'rubygems'
require 'builder'
require 'hpricot'
require 'json'
require 'open-uri'
require 'rack/conneg'
require 'sinatra'
require 'yaml'

use(Rack::Conneg) { |conneg|
  conneg.ignore('/public/')
  conneg.provide([:json, :xml])
}

configure do
end

before do
  # Force s.id to be an array type
  request.env['QUERY_STRING'] = request.env['QUERY_STRING'].gsub(/s\.id=/,'s.id[]=')
  params['s.id'] = request.params['s.id']
  content_type negotiated_format
end

helpers do

  def get_availabilities(bibs)
    start_time = Time.now
    result = { 'version' => '0.0.1', 'availabilityItems' => [] }
    bibs.each { |bib|
      result['availabilityItems'] << get_availability(bib)
    }
    result['totalRequestTime'] = (Time.now - start_time).round
    return result
  end

  def get_availability(bib)
    result = { 'id' => bib, 'availabilities' => [] }
    millennium_uri = "http://oasis.oregonstate.edu/record=#{bib}"
    page = Hpricot(open(millennium_uri))
    page.search('.bibItemsEntry').each do |item|
      data = item.children.collect { |c| c.inner_text.strip.gsub(/\302\240/,'') }.reject { |t| t.empty? }
      location = data.first
      status = data.last
      result['availabilities'] << { 
        'displayString' => "#{status}, #{location}", 
        'status' => status =~ /^(AVAILABLE|INTERNET|LIB USE|NEW )/ ? 'available' : 'unavailable',
        'statusMessage' => status,
        'locationString' => location
      }
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
                  :statusMessage => avail['statusMessage'], :locationString => avail['locationString'])
              }
            end
          }
        end
      end
      xml.target!
    }
    wants.js    { data.to_json }
    wants.json  { data.to_json }
    wants.other { error 400, 'Bad Request' }
  end
  
end
