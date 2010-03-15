require 'hpricot'
require 'open-uri'

class OasisScraper < AvailabilityScraper
  
  def get_availability(bib)
    # Make sure we properly format the bib, including leading 'b' and removing
    # check digit.
    bib = "b#{bib[/[0-9]{7}/]}"
    result = { 'id' => bib, 'availabilities' => [] }
    availability_regexp = /^(AVAILABLE|INTERNET|LIB USE|NEW )/
    uri = "http://oasis.oregonstate.edu/record=#{bib}"
    page = Hpricot(open(uri))
  
    result['availabilities'] = page.search('.bibItemsEntry').collect { |item|
      data = item.search('td').collect { |c| 
        t = c.inner_text.gsub(/\302\240/,'').strip
      }
      location = data.first
      status = data.last
      availability = {
        'status' => availability_regexp === data[2] ? 'available' : 'unavailable'
      }
      
      availability['statusMessage'] = '%3$s' % data
      availability['locationString'] = '%1$s' % data
      availability['callNumber'] = '%2$s' % data
      availability['displayString'] = '%3$s, %1$s' % data

      availability
    }
  
    # Bib record 856 fields
    resources = []
    
    page.search('.bibLinks').each { |item|
      item.search('//a').each { |a| 
        resources << ContentAwareHash['url' => a.attributes['href'], 'title' => a.inner_text] 
      }
    }.flatten
    
    # Checkin record 856 fields
    page.search('tr.bibResourceEntry').each { |item|
      cells = item.search('td')
      range = cells[0].inner_text.strip.split(/-/).collect { |d| Date.parse(d) }
      cells[1].search('//a').each { |a| 
        resource = ContentAwareHash['url' => a.attributes['href'], 'title' => a.inner_text]
        resource['start'] = range[0]
        resource['end'] = range[1] unless range[1].nil?
        resources << resource
      }
    }
  
    result['resources'] = resources.uniq
    
    return result
  end
end

