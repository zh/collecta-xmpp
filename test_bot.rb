#!/usr/bin/env ruby

require 'collecta_bot'

#Jabber::debug = true

class SearchBot < Collecta::Bot
  def self.format_result(msg, debug = true)
    begin
      return msg unless payload = Collecta::Payload.new(msg)
      return msg if payload.type == :unknown
      m = "\n#{payload.type}: [#{payload.meta}] "
      if payload.type == :notify
        m += " -> #{payload.body}"
      elsif payload.type == :query
        m += " -> (#{payload.category}) #{payload.title}\n"
        m += payload.body
        if payload.links
          m += "\nLinks: \n"
          m += payload.links.inspect
        end
      else
        return msg
      end
      m
    rescue Exception => e
      puts "[E] #{e.to_s}" if debug
      return msg
    end  
  end  
end  

if __FILE__ == $0
  # register a handler for SIGINTs
  trap(:INT) do
    EM.stop
    exit
  end
  SearchBot.run("config.yml")
end  
