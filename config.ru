require 'rubygems'
require 'sinatra'
require 'availapi'

use Rack::CommonLogger
use Rack::ShowExceptions

set :environment, :production
set :root, File.dirname(__FILE__)
set :app_file, File.join(File.dirname(__FILE__),'availapi.rb')
disable :run

run Sinatra::Application
