require "rubygems"
require "sinatra"
require "nokogiri"
require "net/http"
require "uri"
require "haml"
require "time"
require "sequel"
require "logger"

LURPPIS_URI = "http://lurppis.tumblr.com/post/136246850348/my-articles"

# 02 Oct 2002 15:00:00 +0200
TIME_FORMAT = "%d %b %Y %H:%M:%S %z"  

SELF_URI = "http://lurprss.herokuapp.com/rss"

UPDATE_INTERVAL = 600

#####################
### DATABASE PART ###
#####################

DB = Sequel.connect(ENV['DATABASE_URL'] || "sqlite:///tmp/lurprss.db")
DB.loggers << Logger.new($stdout)
DB.create_table? :items do
  primary_key :id
  String :url, :null => false
  String :title, :null => false
  DateTime :post_time, :null => false
  DateTime :last_seen_time, :null => false
end

DB.create_table? :last_update do
  primary_key :id
  DateTime :last_update, :null => false
end

def update_database
  uri = URI.parse(LURPPIS_URI)
  http = Net::HTTP.new(uri.host, uri.port)
  html = http.request(Net::HTTP::Get.new(uri.request_uri)).body
  doc = Nokogiri::HTML html
  
  items = DB[:items]
      
  doc.css(".caption > p > a").each do |a|
    item = {}

    item[:title] = a.text.strip
    item[:url] = a["href"]

    updated = items.filter(:url => item[:url]).update(:last_seen_time => Time.now)
    if updated == 0
        item[:post_time] = Time.now
        item[:last_seen_time] = Time.now
        items.insert(item)
    end
  end
  
  killtime = Time.now - UPDATE_INTERVAL
  items.filter{last_seen_time < killtime}.delete
  
  last_update = DB[:last_update]
  last_update.delete
  last_update.insert(:last_update => Time.now)
  
  nil
end

def last_update
  lu = DB[:last_update].select(:last_update).all.first
  if lu
    lu[:last_update]
  else
    Time.now - 2 * UPDATE_INTERVAL
  end
end

def fetch_items(count)
  if last_update < Time.now - UPDATE_INTERVAL
    update_database
  end
  
  DB.from(DB[:items].order(Sequel.desc(:post_time)).limit(count).as(:posts)).all
end

####################
### SINATRA PART ###
####################

configure do
  mime_type :rss, "application/rss+xml"
end

get "/" do
  haml :index, :escape_html => true
end

get "/rss" do
  if params[:count]
    item_count = params[:count].to_i
  else
    item_count = 30
  end
  if item_count <= 0
    item_count = 30
  end

  content_type :rss
  items = fetch_items item_count
  lu = last_update
  haml :rss, :escape_html => true,
       :locals => {:link => LURPPIS_URI,
                   :items => items,
                   :self_href => SELF_URI,
                   :last_build => lu,
                   :time_format => TIME_FORMAT}
end

#################
### HAML PART ###
#################
__END__
@@ index
!!! 5
%html
  %head
    %title lurppis' Writing
    %link{:rel => "alternate",
          :type => "application/rss+xml",
          :title => "lurppis' Writing",
          :href => "/rss"}
  %body
    %h1
      lurppis' Writing
      %a{:href => "/rss"} RSS
    %p
      You can append "?count=10" to reduce the amount of news items. The default is 30.
    %p
      %a{:href => "https://github.com/schwarz/lurppis"} Github
    %p
      %a{:href => "https://github.com/kaini/hnbest"} Based on
@@ rss
!!! XML
%rss{:version => "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom"}
  %channel
    %title lurppis' Writing
    %link= link
    <atom:link href="#{self_href}" rel="self" type="application/rss+xml" />
    %description This feed contains lurppis' writing.
    %lastBuildDate= last_build.strftime(time_format)
    %language en
    -items.each do |item|
      %item
        %title
          <![CDATA[
          item[:title]
          ]]>
        %link= item[:url]
        %guid= item[:url]
        %pubDate= item[:post_time].strftime(time_format)
        %description
          <![CDATA[
          %p
            %a{:href => item[:url]}= item[:title]
          ]]>
