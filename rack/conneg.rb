require 'rack'
require 'mime/types'

module Rack
  
  class Conneg
    
    def initialize(app)
      @app = app
      @ignores = []
      @types = []

      @app.class.module_eval {
        def negotiated_format ; @rack_conneg_format ; end
        def negotiated_type   ; @rack_conneg_type   ; end
        def respond_to
          wants = { :other => Proc.new { raise TypeError, "No handler for #{@conneg_format}" } }
          def wants.method_missing(type, *args, &handler)
            self[type] = handler
          end

          yield wants

          (wants[@rack_conneg_format] || wants[:other]).call
        end
      }
      
      yield self if block_given?
    end
    
    def ignore(route)
      route_re = route.kind_of?(Regexp) ? route : %r{^#{route}}
      @ignores << route_re
    end
    
    def provide(*args)
      args.flatten.each { |type|
        mime_types = MIME::Types[type.to_s]
        if mime_types.empty?
          mime_types = MIME::Types.type_for(type.to_s)
        end
        mime_types.each { |mime_type| @types << mime_type.content_type }
      }
    end
    
    def call(env)
      extension = nil
      path_info = env['PATH_INFO']
      unless @ignores.find { |ignore| ignore.match(path_info) }
        mime_type = MIME::Types.type_for(path_info).first
        if mime_type
          env['PATH_INFO'] = path_info.sub!(/(\..+?)$/,'')
          extension = $1.sub(/^\./,'')
          if !(@types.include?(mime_type.content_type))
            mime_type = nil
          end
        else
          i = 0
          accept_types = env['HTTP_ACCEPT'].split(/,/)
          accept_types.each_with_index { |t,i|
            (accept_type,weight) = t.split(/;/)
            weight = weight.nil? ? 1.0 : weight.split(/\=/).last.to_f
            accept_types[i] = { :type => accept_type, :weight => weight, :order => i }
          }
          accept_types.sort! { |a,b| 
            ord = b[:weight] <=> a[:weight] 
            if ord == 0
              ord = a[:order] <=> b[:order]
            end
            ord
          }
        
          found_type = nil
          accept_types.find { |t|
            re = %r{^#{t[:type].gsub(/\*/,'.+')}$}
            @types.find { |type| re.match(type) ? found_type = type : nil }
          }
          mime_type = MIME::Types[found_type].first
          extension = mime_type.extensions.first
        end
      
        if mime_type
          @app.instance_variable_set('@rack_conneg_format',env['rack.conneg.format'] = extension.to_sym)
          @app.instance_variable_set('@rack_conneg_type',env['rack.conneg.type'] = mime_type)
        end
      end
      @app.call(env) unless @app.nil?
    end
            
  end
  
  class Request
    def negotiated_format ; @env['rack.conneg.format'] ; end
    def negotiated_type   ; @env['rack.conneg.type']   ; end
  end

end