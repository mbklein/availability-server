#!/usr/bin/env ruby

require 'rubygems'
require 'rack/conneg'
require 'sinatra'
require 'preprocessor'
require 'yaml'

begin
  require 'config/scrapers/abstract_scraper'
  scraper_dir = File.join(File.dirname(__FILE__),'config','scrapers')
  Dir.glob(File.join(scraper_dir,'*.rb')).each { |scraper|
    require File.join(scraper_dir,File.basename(scraper,File.extname(scraper)))
  }
end

use(Rack::Preprocessor) { |env|
  # Remove 's.' prefixes from parameters; force params['id'] to be an array type
  env['QUERY_STRING'] = env['QUERY_STRING'].gsub(/\bs\./,'').gsub(/\bid=/,'id[]=')
}

use(Rack::Conneg) { |conneg|
  # TODO: Include some module-independent registration capability in Rack::Conneg
  Rack::Mime::MIME_TYPES['.jsons'] = 'application/x-json-stream'
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.provide([:json,:jsons,:xml])
}

configure do
  config_file = File.join(File.dirname(__FILE__), 'config/config.yml')
  opts = YAML.load(File.read(config_file))
  set :scraper_class, opts[:default_scraper]
  set :scraper_config, opts[:scraper_config]
end

before do
  if negotiated_type
    content_type negotiated_type
  end
end

get '/availability' do
  scraper_class = Kernel.const_get(options.scraper_class)
  if params['scraper']
    scraper_class = Kernel.const_get(params['scraper'])
    unless scraper_class.ancestors.include?(AvailabilityScraper)
      content_type 'text/plain'
      error 400, "Bad Request: #{params['scraper']} is not a subclass of AvailabilityScraper"
    end
  end
  scraper = scraper_class.new(options.scraper_config)
  data = scraper.get_availabilities(params['id'] || [])
  
  respond_to do |wants|
    wants.xml   { data.to_xml   }
    wants.json  { data.to_json  }
    wants.jsons { data.to_jsons }
    wants.other { content_type 'text/plain'; error 400, 'Bad Request' }
  end
  
end

get '/record/:id' do
  # Let's be all HTTP/1.1 about this and use the 303 SEE OTHER status properly,
  # instead of abusing 302 FOUND the way everyone else does.
  redirect "http://oasis.oregonstate.edu/record=#{params[:id]}", 303
end
