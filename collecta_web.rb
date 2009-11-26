#!/usr/bin/env ruby

require 'rubygems'
require 'digest/sha1'
require 'eventmachine'
require 'xmpp4r-simple'
require 'sinatra'
require 'json'
require 'httpclient'
require 'collecta'

begin
  require 'system_timer'
  MyTimer = SystemTimer
rescue
  require 'timeout'
  MyTimer = Timeout
end

class String
  def valid_jid?
    return false if self.length < 2 or self.length > 64 # 2-16 chars
    return false if not self.include?('@')              # @ means full JID
    return false if self =~ /\d+/                       # not only digits
    true
  end
end

module Collecta

  class Search

    attr_accessor :queries, :callbacks, :service, :jid, :noxmpp

    def initialize(jid, apikey, noxmpp)
      @jid = jid
      @noxmpp = noxmpp
      @queries = [] 
      @callbacks = []
      @service = Collecta::Client.new(apikey)
      @service.anonymous_connect
    end

    def subscribed?(query); @queries.include?(query) end 
    def hooked?(url); @callbacks.include?(url) end
    def connected?; @service == nil end

    def subscribe(query)
      unless @queries.include?(query)
        @queries << query
        @service.subscribe(query)
      end
    end 

    def unsubscribe
      @service.unsubscribe 
      @queries = [] 
      @callbacks = []
    end  

    def hook(url)
      return unless url and not url.empty?
      @callbacks << url unless @callbacks.include?(url)
    end  

    def to_s
        msg = "<h2>JID: #{@jid}</h2><pre>\n"
        msg += "HTTP Only?: #{@noxmpp ? 'yes' : 'no'}\n"
        msg += "Queries: #{@queries.inspect}\n"
        msg += "Callbacks: #{@callbacks.inspect}\n"
        msg += "<pre>\n"
        msg += '<br/><br/><a href="/1/admin" onClick="history.go(-1)">Back</a>'
        msg
    end
  end

  class App < Sinatra::Default
    set :sessions, false
    set :run, false
    set :environment, ENV['RACK_ENV']

    configure do
      API_VERSION = "1.2"
      DB = {}
      CFG = YAML.load(File.read("config.yml"))
      XMPP = Jabber::Simple.new(CFG['bot.jid'], CFG['bot.password'])
    end

    helpers do
      def protected!
        response['WWW-Authenticate'] = %(Basic realm="Protected Area") and \
        throw(:halt, [401, "Not authorized\n"]) and \
        return unless authorized?
      end

      def authorized?
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && 
                           @auth.credentials == ['admin', CFG['web.password']]
      end

      # post the search results to a callback url(s) for some JID
      def do_post(jid, payload)
        DB[jid].callbacks.each do |cb|
          begin
            MyTimer.timeout(CFG['web.giveup'].to_i) do
              params = { :meta => payload.meta,
                         :category => payload.category,
                         :title => payload.title,
                         :body => payload.body }
              params[:links] = payload.links if payload.links
              HTTPClient.post(cb, params)
            end
          rescue Exception => e
            case e
            when Timeout::Error
              p "Timeout: #{cb}"
            else  
              p "[E] do_post: #{e.to_s}"
            end
            next
          end
        end   
      end  

      def do_subscribe(jid, query, callback = "", noxmpp = false)
        unless DB[jid]
          DB[jid] = Collecta::Search.new(jid, CFG['collecta.apikey'], noxmpp)
          DB[jid].service.add_message_callback do |msg|
            payload = Collecta::Payload.new(msg)
            text = "[#{payload.meta}] #{payload.category}: #{payload.title}"
            p "#{jid} -> #{text}"
            XMPP.deliver(jid, "#{text}\n#{payload.body}") unless DB[jid].noxmpp == true
            # post the results also to the verified webhook
            do_post(jid, payload) unless DB[jid].callbacks.empty?
          end  
        end
      
        DB[jid].noxmpp = noxmpp
        DB[jid].subscribe(query)
        DB[jid].hook(callback)
      end
    end

    get '/' do
      return "API v#{API_VERSION}"
    end

    get '/1/?' do
      return "API v#{API_VERSION}"
    end  

    post '/1/sub/?' do
      begin
        jid = params[:jid]
        query = params[:q]
        callback = params[:callback]
        noxmpp = params[:noxmpp] ? true : false
        raise "Missing or wrong parameter" unless jid and jid.valid_jid? and query
        sig = Digest::SHA1.hexdigest("--#{CFG['web.apikey']}--#{jid}")
        raise "Non authorized" unless params[:sig] == sig
        do_subscribe(jid, query, callback, noxmpp)
      rescue Exception => e
        throw :halt, [400, "Bad request: #{e.to_s}"]
      end  
      throw :halt, [200, "OK"]
    end

    post '/1/unsub/?' do
      begin
        jid = params[:jid]
        raise "Invalid JID '#{jid}'" unless jid and jid.valid_jid? and DB[jid]
        sig = Digest::SHA1.hexdigest("--#{CFG['web.apikey']}--#{jid}")
        raise "Non authorized" unless params[:sig] == sig
        DB[jid].unsubscribe
      rescue Exception => e
        throw :halt, [400, "Bad request: #{e.to_s}"]
      end  
      throw :halt, [200, "OK"]
    end

    get '/1/list/?' do
      begin
        jid = params[:jid]
        raise "Invalid JID '#{jid}'" unless jid and jid.valid_jid? and DB[jid]
        sig = Digest::SHA1.hexdigest("--#{CFG['web.apikey']}--#{jid}")
        raise "Non authorized" unless params[:sig] == sig
        content_type 'application/json; charset=utf-8'
        js = DB[jid].queries.to_json
        # Allow 'abc' and 'abc.def' but not '.abc' or 'abc.'
        if params[:callback] and params[:callback].match(/^\w+(\.\w+)*$/)
          js = "#{params[:callback]}(#{js})"
        end
        return js
      rescue Exception => e
        throw :halt, [400, "Bad request: #{e.to_s}"]
      end  
    end

    # Debug subscribe
    get '/1/admin/?' do
      protected!
      erb :admin
    end

    post '/1/?' do
      jid = params[:jid]
      mode = params[:mode]
      throw :halt, [400, "Bad request"] unless mode and jid
      raise "Non authorized" unless params[:apikey] == CFG['web.apikey']
      if mode == 'dump'
        throw :halt, [200, DB[jid].to_s]
      elsif mode == 'subscribe'
        query = params[:query]
        throw :halt, [400, "Bad request"] unless query
        callback = params[:callback]
        noxmpp = (params[:noxmpp] == 'yes' and callback and not callback.empty?) ? true : false
        do_subscribe(jid, query, params[:callback], noxmpp)
      elsif mode == 'unsubscribe'
        DB[jid].unsubscribe
      else
        throw :halt, [400, "Bad request, unknown 'mode' parameter"]
      end
      throw :halt, [200, DB[jid].to_s]
    end    

  end
end

if __FILE__ == $0
  Collecta::App.run!
end
