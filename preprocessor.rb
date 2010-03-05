require 'rack'

module Rack
  
  class Preprocessor
    
    def initialize(app, &block)
      @app = app
      @proc = block
    end
   
    def call(env)
      @proc.call(env)
      @app.call(env) unless @app.nil?
    end
    
  end
  
end