require 'xmpp4r'
require 'xmpp4r/pubsub'
require 'crack'

#Jabber::debug = true

module Jabber
  module PubSub
    class ServiceHelper
      # options is a Hash { "key" => "val" }
      # will be converted to <field var='key'><value>val</value></field>
      def subscribe_to_with_options(node, options)
        iq = basic_pubsub_query(:set)
        sub = REXML::Element.new('subscribe')
        sub.attributes['node'] = node
        sub.attributes['jid'] = @stream.jid.strip.to_s
        iq.pubsub.add(sub)
        iq.pubsub.add(Jabber::PubSub::SubscriptionConfig.new(node, @stream.jid, options, nil))
        res = nil
        @stream.send_with_id(iq) do |reply|
          pubsubanswer = reply.pubsub
          if pubsubanswer.first_element('subscription')
            res = PubSub::Subscription.import(pubsubanswer.first_element('subscription'))
          end
        end # @stream.send_with_id(iq)
        res
      end
    end   # class
  end     # module
end       # module


module Collecta
  class Client < Jabber::Client
    attr_reader :node, :service

    def initialize(apikey)
      @apikey = apikey
      @service = "search.collecta.com"
      @node = "search"
      super("guest.collecta.com/search")      
    end

    # no params to connect() will force SRV lookup
    def anonymous_connect
      connect
      if supports_anonymous?
        auth_anonymous_sasl
      else
        raise ClientAuthenticationFailure.new, "ANONYMOUS SASL not supported"  
      end  
      send(Jabber::Presence.new.set_type(:available))
      return self
    end

    def subscribe(query = nil, notify = nil)
      # need at least one of query or notify
      puts "q: #{query}, n: #{notify}"
      raise Jabber::ArgumentError, "Subscription needs: query or notify" unless (query or notify)
      options = { "x-collecta#apikey" => @apikey }
      options["x-collecta#query"] = query if query
      options["x-collecta#notify"] = notify if notify
      @pubsub = Jabber::PubSub::ServiceHelper.new(self, @service)
      return @pubsub.subscribe_to_with_options(@node, options)
    end  

    def unsubscribe
      @pubsub.unsubscribe_from(@node) if @pubsub
    end  
  end  # class


  # Encapsulated Collecta messages
  # http://developer.collecta.com/XmppApi/RealTime/
  class Payload
    attr_reader :raw
  
    def initialize(text)
      begin
        @raw = Crack::XML.parse(text.to_s)
        @item = @raw['message']['event']['items']['item'] if @raw
        self
      rescue
        return nil
      end  
    end
  
    def type
      return :unknown unless @item
      return :notify if @item['count']
      :query
    end
  
    # to which query this message belongs
    def meta
      type = self.type
      return nil if type == :unknown
      return @raw['message']["headers"]["header"].to_s if type == :query
      return @item['id'] if type == :notify
      nil
    end
  
    # return entry like a hash
    def entry
      return nil unless @item and self.type == :query
      @item['entry']
    end
  
    def category
      return nil unless @item and self.type == :query
      @item['entry']['category'].to_s
    end  
  
    def title
      return nil unless @item and self.type == :query
      @item['entry']['title'].to_s
    end  
   
    # Collecta will strip the <content> child from the payload if a <summary> 
    # child is provided. 
    def body
      return nil unless @item
      return @item['count'] if self.type == :notify
      return @item['entry']['summary'] if @item['entry']['summary']
      return @item['entry']['abstract']['p'] unless @item['entry']['content']
      @item['entry']['content']
    end
  
    def abstract
      return nil unless @item
      return @item['count'] if self.type == :notify
      @item['entry']['abstract']['p']
    end
  
    # return array of links
    def links
      return nil unless @item and self.type == :query and @item['entry']['link']
      @item['entry']['link']
    end  
  end  # class
end    # module
