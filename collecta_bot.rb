require 'collecta'
require 'xmpp4r-simple'
require 'eventmachine'

#Jabber::debug = true

class Jabber::Simple
  def subscribed_to?(x); true; end
  def ask_for_auth(x); contacts(x).ask_for_authorization!; end
end

module Collecta  
  class Task
    include EM::Deferrable
  
    def do_subscribe(settings)
      begin
        if !settings["query"] and !settings["notify"]
          raise "need at least one query or notify"
        end  
        Bot.service.subscribe(settings["query"], settings["notify"])
        set_deferred_status(:succeeded)
      rescue Exception => e
        puts e.to_s if settings["debug"]
        set_deferred_status(:failed)
      end
    end
  
    def do_unsubscribe(settings)
      begin
        Bot.service.unsubscribe
        set_deferred_status(:succeeded)
      rescue Exception => e
        puts e.to_s if settings["debug"]
        set_deferred_status(:failed)
      end
    end  
  
  end # class  

  class Bot

    def self.announce(subscribers, messages)
      return unless Bot.client
      Array(subscribers).each do |to|
        Array(messages).each do |body|
          Bot.client.deliver(to, body)
        end
      end
    end

    def self.client
      @@socket
    end

    def self.service
      @@search
    end  

    # redefine this function in your bots
    def self.format_result(msg, debug = true)
      begin
        return msg unless payload = Collecta::Payload.new(msg)
        return msg if payload.type == :unknown
        return "[#{payload.meta}] #{payload.category}: #{payload.title}"
      rescue Exception => e
        puts "[E] #{e.to_s}" if debug
      end  
    end  

    def self.run(config_fname)
      settings = YAML.load(File.read(config_fname))
      @@socket = Jabber::Simple.new(settings["bot.jid"], settings["bot.password"])
      @@socket.accept_subscriptions = true

      @@search = Collecta::Client.new(settings["collecta.apikey"])
      @@search.anonymous_connect
      puts "Connected: #{@@search.jid.to_s}" if settings["debug"]

      Bot.service.add_message_callback do |msg|
        puts "M: #{msg.inspect}" if settings["debug"]
        Bot.client.deliver(settings["bot.console"], self.format_result(msg, settings["debug"]))
      end  

      at_exit do
        Bot.service.unsubscribe
        Bot.client.disconnect
      end

      EM.epoll
      EM.run do
        EM::PeriodicTimer.new(0.05) do
         
          Bot.client.received_messages do |msg|
            
            from = msg.from.strip.to_s
            next unless (msg.type == :chat and not msg.body.empty?)
            cmdline = msg.body.split

            case cmdline[0]
            when "HELP", "H", "help", "?":
              # TODO better help
              help = "HELP, PING"
              help += ", S, N, UN" if from == settings["bot.console"]
              Bot.client.deliver(from, help)
            when "PING", "ping", "Ping":
              @@socket.ask_for_auth(msg.from)
              Bot.client.deliver(from, "PONG ;)")
            # Subscribe to query or notify  
            when "S", "s", "N", "n"
              next unless (from == settings["bot.console"] and cmdline[1])
              EM.spawn do
                # TODO validate the query
                type = (cmdline[0].downcase == "s") ? "query" : "notify"
                settings[type] = msg.body.slice(2, msg.body.length)
                task = Task.new
                task.callback { 
                  puts "Subscribed to #{type}: #{settings[type]}" if settings["debug"]
                  Bot.client.deliver(from, "Subscribed to #{type}: #{settings[type]}") 
                }
                task.errback  { Bot.client.deliver(from, "Subscription failed") }
                task.do_subscribe(settings)
              end.notify
            # UnSubscribe
            when "UN", "un", "U", "u"
              next unless from == settings["bot.console"]
              EM.spawn do
                task = Task.new
                task.callback { Bot.client.deliver(from, "Unsubscribed from all searches") }
                task.errback  { Bot.client.deliver(from, "Unsubscribe failed") }
                task.do_unsubscribe(settings)
              end.notify
            end  # case
          end
        end  # EM::Timer  
      end    # EM.run  
    end      # Bot::run 
  
  end  # Bot
end    # module


if __FILE__ == $0
  # register a handler for SIGINTs
  trap(:INT) do
    EM.stop
    exit
  end
  Collecta::Bot.run("config.yml")
end  
