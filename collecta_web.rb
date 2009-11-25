#!/usr/bin/env ruby

require 'rubygems'
require 'eventmachine'
require 'xmpp4r-simple'
require 'sinatra'
require 'collecta'

class String
  def valid_jid?
    return false if self.length < 2 or self.length > 64 # 2-16 chars
    return false if not self.include?('@')              # @ means full JID
    return false if self =~ /\d+/                       # not only digits
    true
  end
end

module Collecta
  class App < Sinatra::Default
    set :sessions, false
    set :run, false
    set :environment, ENV['RACK_ENV']

    configure do
      API_VERSION = "1.2"
      QUERIES = {}
      CONN = {}
      CFG = YAML.load(File.read("config.yml"))
      XMPP = Jabber::Simple.new(CFG['bot.jid'], CFG['bot.password'])
    end

    get '/' do
      return "API v#{API_VERSION}"
    end

    get '/1/?' do
      return "API v#{API_VERSION}"
    end  

    post '/1/sub/?' do
      begin
        raise "Non authorized" unless params[:apikey] == CFG['web.apikey']
        jid = params[:jid]
        query = params[:q]
        raise "Missing or wrong parameter" unless jid and jid.valid_jid? and query
        if CONN[jid]
          @service = CONN[jid]
        else
          @service = Collecta::Client.new(CFG["collecta.apikey"])
          @service.anonymous_connect
          @service.add_message_callback do |msg|
            payload = Collecta::Payload.new(msg)
            text = "[#{payload.meta}] #{payload.category}: #{payload.title}"
            p "#{jid} -> #{text}"
            XMPP.deliver(jid, "#{text}\n#{payload.body}")
          end  
          CONN[jid] = @service
        end

        if QUERIES[jid]
          QUERIES[jid] << query
        else
          QUERIES[jid] = Array(query)
        end
        @service.subscribe(query)
      rescue Exception => e
        throw :halt, [400, "Bad request: #{e.to_s}"]
      end  
      throw :halt, [200, "OK"]
    end

    post '/1/unsub/?' do
      begin
        raise "Non authorized" unless params[:apikey] == CFG['web.apikey']
        jid = params[:jid]
        raise "Invalid JID '#{jid}'" unless jid and jid.valid_jid? and CONN[jid]
        CONN[jid].unsubscribe
        QUERIES.delete(jid) if QUERIES[jid]
      rescue Exception => e
        throw :halt, [400, "Bad request: #{e.to_s}"]
      end  
      throw :halt, [200, "OK"]
    end
  end
end

if __FILE__ == $0
  Collecta::App.run!
end
