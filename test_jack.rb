#!/usr/bin/env ruby

require 'rubygems'
require 'switchboard'
require 'switchboard/helpers/pubsub'
require 'collecta_jack'

#Jabber::debug = true

settings = YAML.load(File.read("test_config.yml"))
switchboard = Switchboard::CollectaClient.new(settings["collecta.apikey"], ARGV.pop, nil, true)

switchboard.on_collecta_message do |msg|
  payload = Collecta::Payload.new(msg)
  puts payload.raw.inspect
end  

switchboard.run!
