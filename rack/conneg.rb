require 'rack'
require 'mime/types'

module Rack
  class Request
    
    def negotiated_format
      @env['rack.conneg.format']
    end
    
    def negotiated_type
      @env['rack.conneg.type']
    end
    
    def negotiate(available_types)
      unless @env['rack.conneg.format']
        mime_type = MIME::Types.type_for(self.path_info).first
        extension = nil
        if mime_type
          self.path_info.sub!(/(\..+?)$/,'')
          extension = $1.sub(/^\./,'')
        else
          i = 0
          accept_types = env['HTTP_ACCEPT'].split(/,/).collect { |t|
            i += 1
            (accept_type,weight) = t.split(/;/)
            weight = weight.nil? ? 1.0 : weight.split(/\=/).last.to_f
            { :type => accept_type, :weight => weight, :order => i }
          }.sort { |a,b| 
            ord = b[:weight] <=> a[:weight] 
            if ord == 0
              ord = a[:order] <=> b[:order]
            end
            ord
          }
          
          found_type = accept_types.find { |t|
            re = %r{^#{t[:type].gsub(/\*/,'.+')}$}
            available_types.find { |at| re.match(at) } ? t : nil
          }
          mime_type = MIME::Types[found_type[:type]].first
          extension = mime_type.extensions.first
        end
        
        if mime_type
          @env['rack.conneg.format'] = extension.to_sym
          @env['rack.conneg.type'] = mime_type
        else
          @env['rack.conneg.format'] = nil
          @env['rack.conneg.type'] = nil
        end
      end
      @env['rack.conneg.type']
    end
    
    def respond_to
      wants = { :other => Proc.new { raise TypeError, "No handler for #{negotiated_format}" } }
      def wants.method_missing(type, *args, &handler)
        self[type] = handler
      end
      
      yield wants
      
      (wants[negotiated_format] || wants[:other]).call
    end
    
  end
end