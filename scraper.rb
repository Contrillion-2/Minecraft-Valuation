require 'open-uri'
require 'hpricot'
require "cgi"
require "uri"
require "net/https"
require "rexml/document"
require 'yaml'
require 'pg'

class Scraper

  def go
    start
  end

  private

  def curr_exchange_rate
    url = URI.parse("http://api.finance.xaviermedia.com/api/latest.xml")

    resp = Net::HTTP.get(url)
    xml  = REXML::Document.new(resp)

    xml.elements.each("//exchange_rates/fx") { |el|
      if el.elements[1].text == "USD"
        return el.elements[2].text.to_f
      end
    }

    return 1.0

  end

  def start

    doc = open("http://www.minecraft.net/stats.jsp") { |f| Hpricot(f) }

    @text = (doc/"/html/body/div[2]/p").inner_html

    if (@text =~ /(\d+) people bought the game/)
      @number = $1.to_i
    else
      puts "Could not find string"
      return
    end

    yaml_location = File.dirname(__FILE__) + '/config/constants.yml'
    if ( data = YAML::load_file(yaml_location) )
      @since = data['since']
      rent = data['rent']                 #Euros per sqft per year
      office_space = data['office_space'] #Square Feet for 6 people
      salary = data['salary']             #Pretty good salary
      employees = data['employees']       #As Notch has said
      networking = data['networking']     #Monthly cost * Number of months
      msc_sga = data['misc_sga']          #For things I can't remember
    else
      puts "Could not load YAML file"
      return
    end


    office_cost = rent * office_space
    salary_cost = salary * employees

    sga = misc_sga + office_cost + salary_cost + networking

    @top_line = (@number * 9.4 * 365).to_i

    @eu_value = (@top_line - sga) * 3 #Times 3 multiplyer
    @us_value = (@eu_value * curr_exchange_rate).to_i 

    @avg = @eu_value #In case one can't retrerive it from the database

    get_last_avg = "SELECT average FROM data ORDER BY timestamp DESC LIMIT 1"

    sql_insert = "INSERT INTO data (top_line, eu_value, us_value, average) VALUES ($1, $2, $3, $4)"

    db_location = File.dirname(__FILE__) + '/config/database.yml'
    db_config = YAML::load_file(db_location)
    conn = PGconn.open(db_config)

    res = conn.exec(get_last_avg)
    @avg = res[0][0].to_i

    conn.exec(sql_insert,[@top_line, @eu_value, @us_value, ((@eu_value+@avg)/2).to_i])
  end
end