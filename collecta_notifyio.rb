#!/usr/bin/env ruby

require 'rubygems'
require 'collecta'
require 'httpclient'
require 'jcode'

$KCODE = 'UTF8'

begin
  require 'system_timer'
  MyTimer = SystemTimer
rescue
  require 'timeout'
  MyTimer = Timeout
end

class String
  def strip_tags
    gsub(/<.+?>/,'').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').
                     gsub(/&ellip;/,'...').gsub(/&apos;/, "'")
  end
  def condense
    gsub("\n",'').gsub("\r",' ').gsub("\t",' ').gsub(/\s+/,' ')
  end
  # 140 - "...".length
  def truncate(limit = 137)
    self.match(%r{^(.{0,#{limit}})})[1]
  end
  def auto_link
    gsub /((https?:\/\/|www\.)([-\w\.]+)+(:\d+)?(\/([\w\/_\.]*(\?\S+)?)?)?)/, %Q{<a href="\\1">\\1</a>}
  end  
end  

#Jabber::debug = true

@debug = true
#@notify = ["windows", "vista"]

@settings = YAML.load(File.read("config.yml"))
@client = Collecta::Client.new(@settings["collecta.apikey"])
@notifyio_url = "http://api.notify.io/v1/notify/#{@settings['notifyio.userhash']}?api_key=#{@settings['notifyio.apikey']}"
@client.anonymous_connect
puts "Connected: #{@client.jid.to_s}" if @debug

while @query = ARGV.pop 
  # Let's connect to the Pubsub service
  if @client.subscribe(@query, nil) and @debug
    msg = "Subscribed: '#{@query}'"
    puts msg
  end
end

@client.add_message_callback do |msg|
  begin
    next unless payload = Collecta::Payload.new(msg)
    next if payload.type == :unknown
    title = "[#{payload.category}]: #{payload.title.strip_tags.condense.truncate}..."
    puts title
    text = "#{payload.body.strip_tags.condense.auto_link}"
    query = { 'title' => title,
              'text'  => text,
              'icon'  => 'http://developer.collecta.com/favicon.ico' }
    if payload.links
      link = Array(payload.links)[0]
      query['link'] = link['href'] if link.kind_of?(Hash)
    end  
    MyTimer.timeout(5) do
      res = HTTPClient.post(@notifyio_url, query)
      status = res.status.to_i
      raise "invalid message: #{title}" if (status < 200 or status >= 300)
    end
  rescue Exception => e
    puts "[E] #{e.to_s}"
    next
  end  
end

# register a handler for SIGINTs
trap(:INT) do
  exit
end

at_exit do
  @client.unsubscribe
  puts "UnSubscribed." if @debug
  @client.close
end

Thread.stop
