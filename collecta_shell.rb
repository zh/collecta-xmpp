#!/usr/bin/env ruby

require 'rubygems'
require 'eventmachine'
require 'xmpp4r-simple'
require 'em-http'
require 'pp'
require 'collecta'

$stdout.sync = true

@@queries = {}
@@connections = {}
@@settings = {}

class String
  def valid_jid?
    return false if self.length < 2 or self.length > 64 # 2-16 chars
    return false if not self.include?('@')              # @ means full JID
    return false if self =~ /\d+/                       # not only digits
    true
  end
end

class Task
  include EM::Deferrable
  def subscribe(jid, query, &block)
    begin
      raise "Missing or wrong parameter" unless jid and query and jid.valid_jid?
      if @@connections[jid]
        @service = @@connections[jid]
      else
        @service = Collecta::Client.new(@@settings["collecta.apikey"])
        @service.anonymous_connect
        @service.add_message_callback(&block)
        @@connections[jid] = @service
      end

      if @@queries[jid]
        @@queries[jid] << query
      else
        @@queries[jid] = Array(query)
      end
      @service.subscribe(query)
      set_deferred_status(:succeeded)
    rescue Exception => e
      p "[E] sub: #{e.to_s}"
      set_deferred_status(:failed)
    end  
  end

  def unsubscribe(jid)
    begin
      raise "Missing or wrong parameter" unless jid and jid.valid_jid? and @@connections[jid]
      @@connections[jid].unsubscribe
      @@queries.delete(jid) if @@queries[jid]
      set_deferred_status(:succeeded)
    rescue Exception => e
      p "[E] unsub: #{e.to_s}"
      set_deferred_status(:failed)
    end  
  end  
end

class KbHandler < EM::Connection
  include EM::Protocols::LineText2

  def post_init
    print "> "
  end

  def receive_line(line)
    line.chomp!
    line.gsub!(/^\s+/, '')

    cmdline = line.split   
    case(cmdline[0])
    when "sub","s" then
      jid = cmdline[1]
      query =  line.sub(cmdline[0],"").sub(cmdline[1],"").strip
      EM.spawn do
        task = Task.new
        task.callback { p "'#{jid}' subscribed to '#{query}'"; print "> " }
        task.errback { p "[E] subscription failed."; print "> " }
        task.subscribe(jid, query) do |msg|
          payload = Collecta::Payload.new(msg)
          text = "[#{payload.meta}] #{payload.category}: #{payload.title}"
          p "#{jid} -> #{text}"
          @@xmpp.deliver(jid, "#{text}\n#{payload.body}")
          print "> " 
        end  
      end.notify  
      print "> " 

    when "unsub","u" then
      jid = cmdline[1]
      EM.spawn do
        task = Task.new
        task.callback { p "'#{jid}' unsubscribed from all queries"; print "> " }
        task.errback { p "unsubscription failed"; print "> " }
        task.unsubscribe(jid)
      end.notify  
      print "> "

    when "list","l" then
      @@queries.each { |k,v|
        print "#{k}: #{v.inspect}\n"
      }  
      print "> "

    when "exit","quit","e","q" then
      @@connections.each { |k,v| p "unsubscribe #{k}"; v.unsubscribe }
      EM.stop

    when "help","h","?" then
      p "sub JID QUERY - subscribe JID to QUERY"
      p "unsub JID     - unsubscribe JID"
      p "exit          - exits the app"
      p "help          - this help"
      print "> "
    end
  end
end

EM.epoll
EM.run do
  @@settings = YAML.load(File.read("config.yml"))
  @@xmpp = Jabber::Simple.new(@@settings['bot.jid'], @@settings['bot.password'])
  EM.open_keyboard(KbHandler)
end

puts "Finished"
