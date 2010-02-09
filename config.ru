require 'rubygems'
require 'sinatra'

set :environment, :production
disable :run

require 'availapi'
run Sinatra::Application
