#!/usr/bin/env ruby

require 'rubygems'
require 'builder'
require 'hpricot'
require 'json'
require 'open-uri'
require 'rack'
require 'yaml'

module Availability
  
  RESPONSE_TYPES = [
    {
      :converter => lambda { |data|
        xml = Builder::XmlMarkup.new
        xml.availabilityResponse do
          xml.version data['version']
          xml.totalRequestTime data['totalRequestTime']
          xml.availabilityItems do
            data['availabilityItems'].each { |item|
              xml.item(:id => item['id']) do
                item['availabilities'].each { |avail|
                  xml.availability do
                    xml.displayString avail['displayString']
                    xml.status avail['status']
                    xml.statusMessage avail['statusMessage']
                    xml.loationString avail['locationString']
                  end
                }
              end
            }
          end
        end
        return xml.target!
      },
      :extensions => ['.xml'],
      :mime_types => ['application/xml']
    },
    {
      :converter => lambda { |data| data.to_json },
      :extensions => ['.json'],
      :mime_types => ['application/json','text/json']
    }
  ]
  
  class Service

    def make_response(req,data)
      responder = nil
      output_type = ''
      ext = File.extname(req.script_name)
      if ext.empty?
        acceptable_types = req.env['HTTP_ACCEPT'].split(/,/).collect { |at| at.split(/;/).first }
        responder = RESPONSE_TYPES.find { |rt| 
          found_types = rt[:mime_types] & acceptable_types
          if found_types.length > 0
            output_type = found_types.first
            true
          else
            false
          end
        }
      else
        responder = RESPONSE_TYPES.find { |rt| rt[:extensions].include?(ext) }
        output_type = responder[:mime_types].first
      end
      
      res = Rack::Response.new
      if responder.nil?
        res.status = 400
      else
        res.status = 200
        res.header['Content-Type'] = output_type
        res.write(responder[:converter].call(data))
      end
      return res
    end
  
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
      page = Hpricot(open("http://oasis.oregonstate.edu/record=#{bib}"))
      page.search('.bibItemsEntry').each do |item|
        data = item.children.collect { |c| c.inner_text.strip.gsub(/\302\240/,'') }.reject { |t| t.empty? }
        location = data.first
        status = data.last
        result['availabilities'] << { 
          'displayString' => "#{status}, #{location}", 
          'status' => status =~ /^(AVAILABLE|INTERNET|LIB USE)/ ? 'available' : 'unavailable',
          'statusMessage' => status,
          'locationString' => location
        }
      end
      return result
    end

    def call(env)
      env['QUERY_STRING'].gsub!(/s.id=/,'s.id[]=')
      req = Rack::Request.new(env)
      result = get_availabilities(req.params['s.id'] || [])
      res = make_response(req,result)
      res.finish
    end
  
  end

end
