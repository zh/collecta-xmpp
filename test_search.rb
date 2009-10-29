#!/usr/bin/env ruby

require 'rubygems'
require 'collecta'

#Jabber::debug = true

@debug = true
#@notify = ["windows", "vista"]

settings = YAML.load(File.read("test_config.yml"))
@client = Collecta::Client.new(settings["collecta.apikey"])
@client.anonymous_connect
puts "Connected: #{@client.jid.to_s}" if @debug

while @query = ARGV.pop 
  # Let's connect to the Pubsub service
  if @client.subscribe(@query, @notify) and @debug
    msg = "Subscribed "
    msg += " query: '#{@query}'" if @query
    msg += " , notify: #{@notify.inspect}" if @notify
    puts msg
  end
end

@client.add_message_callback do |msg|
  begin
    next unless payload = Collecta::Payload.new(msg)
    next if payload.type == :unknown
    m = "#{payload.type}: #{payload.meta} "
    if payload.type == :notify
       m += " -> #{payload.body}"
    elsif payload.type == :query
      m += "\n---\n"
      m += "#{payload.category}: #{payload.title}\n"
      m += payload.body
      if payload.links
        m += "\n---\n"
        m += payload.links.inspect
      end
    else
      next  
    end
    m += "\n===============\n\n"
    puts m
  rescue Exception => e
    puts "[E] #{e.to_s}"
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
