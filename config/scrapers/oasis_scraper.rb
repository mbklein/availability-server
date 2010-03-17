require 'hpricot'
require 'open-uri'

class OasisScraper < AvailabilityScraper
  
  def get_availability(bib)
    # Make sure we properly format the bib, including leading 'b' and removing
    # check digit. But put the *original* bib in the output, since the client
    # will probably be keying off of it.
    result = { 'id' => bib, 'availabilities' => [] }
    bib = "b#{bib[/[0-9]{7}/]}"
    result['bib'] = bib
    availability_regexp = /^(AVAILABLE|INTERNET|LIB USE|NEW )/
    uri = "http://oasis.oregonstate.edu/record=#{bib}"
    page = Hpricot(open(uri))
    content_wrapper = page.search('div.bibContentWrapper').first || page

    # Bib record 856 fields
    resources = []
    availabilities = []
    
    content_wrapper.search('.bibLinks').each { |item|
      item.search('//a').each { |a| 
        resources << ContentAwareHash['url' => a.attributes['href'], 'title' => a.inner_text] 

        link_text = a.inner_text.split(/--/).last.strip
        availabilities << ContentAwareHash[
          'status' => 'available',
          'statusMessage' => 'AVAILABLE',
          'locationString' => %{<a href="#{a.attributes['href']}" target="_new">#{link_text}</a>},
          'displayString' => %{AVAILABLE, <a href="#{a.attributes['href']}" target="_new">#{link_text}</a>}
        ]
      }
    }.flatten
    
    # Checkin record 856 fields
    content_wrapper.search('tr.bibResourceEntry').each { |item|
      cells = item.search('td')
      $stderr.puts cells[0].inner_text.strip
      ranges = parse_date_ranges(cells[0].inner_text.strip)
      cells[1].search('//a').each_with_index { |a,i| 
        puts i
        range_text = ranges[i]
        puts range_text
        range = range_text.split(/-/).collect { |d| Date.parse(d) }
        resource = ContentAwareHash['url' => a.attributes['href'], 'title' => a.inner_text]
        resource['start'] = range[0]
        resource['end'] = range[1] unless range[1].nil?
        resources << resource
        
        link_text = a.inner_text.split(/--/).last.strip
        availabilities << ContentAwareHash[
          'status' => 'available',
          'statusMessage' => "AVAILABLE (#{range_text})",
          'locationString' => %{<a href="#{a.attributes['href']}" target="_new">#{link_text}</a>},
          'displayString' => %{AVAILABLE (#{range_text}) via <a href="#{a.attributes['href']}" target="_new">#{link_text}</a>}
        ]
      }
    }

    holdings = []
    content_wrapper.search('td.bibHoldingsLabel').each { |item| 
      # Ugliest. String transformation. EVER.
      # Remove \302\240, leading/trailing whitespace, internal \r\n's, and trailing colons, then
      # convert to Title Case.
      key = item.inner_text.gsub(/\302\240/,'').strip.gsub(/[\r\n]/,' ').sub(/\s*:\s*$/,'').downcase.gsub(/\b(.)/) { |m| m.upcase }
      if key == 'Location'
        holdings << { }
      end
      holdings.last[key] = item.next_sibling.inner_text.gsub(/\302\240/,'').strip.gsub(/[\r\n]/,' ')
    }
    if holdings.empty?  
      content_wrapper.search('.bibItemsEntry').each { |item|
        data = item.search('td').collect { |c| 
          t = c.inner_text.gsub(/\302\240/,'').strip
        }
        
        availabilities << {
          'status' => availability_regexp === data[2] ? 'available' : 'unavailable',
          'statusMessage' => '%3$s' % data,
          'locationString' => '%1$s' % data,
          'callNumber' => '%2$s' % data,
          'displayString' => '%3$s, %1$s, %2$s' % data,
        }
      }
    else
      holdings.each { |holding|
        availabilities << { 
          'status' => 'available',
          'locationString' => holding['Location'],
          'statusMessage' => "LIBRARY OWNS #{holding['Library Owns']}",
          'displayString' => "LIBRARY OWNS #{holding['Library Owns']} / #{holding['Location']}"
        }
      }
    end
    
    result['availabilities'] = availabilities.uniq
    result['resources'] = resources.uniq
    
    return result
  end
  
  private
  def parse_date_ranges(str)
    re = /([A-Za-z]+\.?\s+[0-9]{1,2},\s+[0-9]{4}(?:\s*-\s*)?)/

    segments = str.scan(re).flatten
    end_range = ''
    segments.reverse.collect { |s|
      s.strip!
      if s =~ /-\s*$/
        end_range.empty? ? s : s + end_range
      else
        end_range = s
        nil
      end
    }.compact.reverse
  end
  
end

