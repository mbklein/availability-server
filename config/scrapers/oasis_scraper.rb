require 'hpricot'
require 'open-uri'

class OasisScraper < AvailabilityScraper

  SUMMARY_LINK_RE = /(contents|finding aid)/i
  
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
    availabilities = []
    
    content_wrapper.search('.bibLinks').each { |item|
      item.search('//a').each { |a| 
        link_title = a.inner_text.split(/--/).last.strip
        availabilities << ContentAwareHash[
          'status' => 'available',
          'statusMessage' => 'AVAILABLE',
          'locationString' => %{<a href="#{a.attributes['href']}" target="_new">#{link_title}</a>},
          'displayString' => %{AVAILABLE, <a href="#{a.attributes['href']}" target="_new">#{link_title}</a>},
          'priority' => link_title =~ SUMMARY_LINK_RE ? 3 : 1,
          'index' => availabilities.length,
          'href' => a.attributes['href'],
          'link_title' => link_title
        ]
      }
    }.flatten
    
    # Checkin record 856 fields
    content_wrapper.search('tr.bibResourceEntry').each { |item|
      cells = item.search('td')
      ranges = parse_date_ranges(cells[0].inner_text.strip)
      cells[1].search('//a').each_with_index { |a,i| 
        range_text = ranges[i]
        range = range_text.split(/-/).collect { |d| Date.parse(d) }
        
        href=a.attributes['href']
        link_title = a.inner_text.split(/--/).last.strip
        availability= ContentAwareHash[
          'status' => 'available',
          'statusMessage' => "AVAILABLE (#{range_text})",
          'locationString' => %{<a href="#{href}" target="_new">#{link_title}</a>},
          'displayString' => %{AVAILABLE (#{range_text}) via <a href="#{href}" target="_new">#{link_title}</a>},
          'priority' => 1,
          'index' => availabilities.length,
          'href' => href,
          'link_title' => link_title
        ]
        availability['date_start'] = range[0]
        availability['date_end'] = range[1] unless range[1].nil?
        availabilities << availability
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
        
        availabilities << ContentAwareHash[
          'status' => availability_regexp === data[2] ? 'available' : 'unavailable',
          'statusMessage' => '%3$s' % data,
          'locationString' => '%1$s' % data,
          'callNumber' => '%2$s' % data,
          'displayString' => '%3$s, %1$s, %2$s' % data,
          'priority' => 2,
          'index' => availabilities.length
        ]
      }
    else
      holdings.each { |holding|
        availabilities << ContentAwareHash[ 
          'status' => 'available',
          'locationString' => holding['Location'],
          'statusMessage' => "LIBRARY OWNS #{holding['Library Owns']}",
          'displayString' => "LIBRARY OWNS #{holding['Library Owns']} / #{holding['Location']}",
          'priority' => 2,
          'index' => availabilities.length
        ]
      }
    end
    
    availabilities.sort! { |a,b| 
      order = a['priority'] <=> b['priority']
      # Ensure stable sort; i.e., items of equal priority stay in their original order
      if order == 0
        order = a['index'] <=> b['index']
      end
      order
    }

    availabilities.each { |availability|
      ### BEGIN TEMPORARY FIX TO FOOL THE SUMMON SCRAPER - REMOVE FOR 3/26 ITERATION ###
#      availability['displayString'] = availability['statusMessage']
      ### END   TEMPORARY FIX TO FOOL THE SUMMON SCRAPER - REMOVE FOR 3/26 ITERATION ###
      availability.delete('priority')
      availability.delete('index')
    }
    
    result['availabilities'] = availabilities.uniq
    
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

