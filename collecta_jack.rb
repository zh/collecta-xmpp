require 'switchboard'
require 'switchboard/helpers/pubsub'
require 'collecta'

#Jabber::debug = true

module Switchboard
  class AnonymousClient < Client
protected
    def auth!
      client.auth_anonymous_sasl
      @roster = Jabber::Roster::Helper.new(client)
    rescue Jabber::ClientAuthenticationFailure => e
      puts "Could not authenticate as #{settings["jid"]}"
      shutdown(false)
      exit 1
    end
  end

  class CollectaClient < AnonymousClient
    DEFAULTS = {
      "jid" => "guest.collecta.com",
      "resource" => "search",
      "pubsub.server" => "search.collecta.com",
      "pubsub.node" => "search",
    }
   
    def initialize(apikey, query = nil, notify = nil, debug = false)
      settings = {
        "debug" => debug,
        "collecta.apikey" => apikey,
        "collecta.query"  => query,
        "collecta.notify"  => notify
      }  
      super(DEFAULTS.merge(settings), true)
      plug!(CollectaJack)
    end  
  end  
end  


class CollectaJack
  def self.connect(switchboard, settings)
    unless settings["pubsub.server"] and settings["pubsub.node"] and settings["collecta.apikey"]
      puts "Needed PubSub server, PubSub node and a Collecta API key"
      return false
    end
    
    switchboard.plug!(AutoAcceptJack, NotifyJack, PubSubJack)

    switchboard.hook(:collecta_message)

    switchboard.on_startup do
      @pubsub = Jabber::PubSub::ServiceHelper.new(client, settings["pubsub.server"])
      options = { "x-collecta#apikey" => settings["collecta.apikey"] }
      options["x-collecta#query"] = settings["collecta.query"] if settings["collecta.query"]
      options["x-collecta#notify"] = settings["collecta.notify"] if settings["collecta.notify"]
      @pubsub.subscribe_to_with_options(settings["pubsub.node"], options) 
      client.add_message_callback do |msg|
        on(:collecta_message, msg)
      end  
    end
  end
end
