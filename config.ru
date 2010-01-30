require 'availapi'
require 'rack/builder'

use Rack::CommonLogger
use Rack::ShowExceptions

availability = Availability::Service.new

map "/availability" do
  run availability
end

Availability::RESPONSE_TYPES.each { |rt|
	rt[:extensions].each { |ext|
		map "/availability#{ext}" do
		  run availability
		end
	}
}
