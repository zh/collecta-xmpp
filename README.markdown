## Collecta XMPP API Ruby Library

Ruby library for easy working with the [Collecta XMPP API](http://developer.collecta.com/XmppApi/).

## Required gems and libraries

 * xmpp4r - low level XMPP manipulations
 * crack - XML parsing
 * switchboard - only for collecta_jack.rb
 * xmpp4-simple - only for collecta_bot.rb
 * eventmachine - only for collecta_bot.rb

## Implemented features

### collecta.rb

 * _Jabber::PubSub::ServiceHelper::subscribe\_to\_with\_options()_ function for passing Data Forms option on node subscription
 * _Collecta::Client_ (inheriting _Jabber::Client_) for SASL ANONYMOUS connection, PubSub (un)subscription etc.
 * _Collecta::Payload_ class, encapsulating Collecta Messages (XML to Hash conversion is done via [Crack](http://github.com/jnunemaker/crack)

### collecta_jack.rb

 * _Switchboard::AnonymousClient_ (inheriting _Switchboard::Client_) for SASL ANONYMOUS connection
 * _Switchboard::CollectaClient_ (inheriting _Switchboard::AnonymousClient_) and adding Collecta default settings (service URL, node etc.)
 * _CollectaJack_ - [Switchboard Jack](http://mojodna.net/2009/07/19/switchboard-as-a-framework.html) for PubSub subscription etc.

_test\_search.rb_ and _test\_jack.rb_ for library testing and  demonstration.

### collecta_bot.rb

 * _Collecta::Task_ - EventMachine::Deferrable - based - background processing for long-running tasks
 * _Collecta::Bot_  - EventMachine -based XMPP bot, sending results from the Collecta searches to some JID

## Usage

Download the library from the [GitHub repository](http://github.com/zh/collecta-xmpp) and copy all files inside your project's sources directory.
Be sure to pass your [Collecta API key](http://developer.collecta.com/KeyRequest/) on the _Collecta::Client.connect()_ function invoking.

### Working directly with xmpp4r

    require 'collecta'

    apikey = "..."
    query, notify = "iphone", "apple, mac"

    @client = Collecta::Client.new(apikey)
    @client.anonymous_connect
    # search for 'iphone' and notifications for 'apple' and 'mac'
    @client.subscribe(query, notify)
    @client.add_message_callback do |msg|
        next unless payload = Collecta::Payload.new(msg)
        # do something with the messages
    end
    ...
    at_exit do
        @client.unsubscribe
        @client.close
    end

### Working with switchboard

    require 'collecta_jack'
    
    settings = YAML.load(File.read("config.yml"))
    # query from the command line, no notifications, debug enabled
    switchboard = Switchboard::CollectaClient.new(settings["collecta.apikey"], ARGV.pop, nil, true)
    
    switchboard.on_collecta_message do |msg|
        payload = Collecta::Payload.new(msg)
        # do something with the messages
    end
     
    switchboard.run!

### XMPP Bot

Available Bot Commands

 * __HELP__ - just a commands list. TODO: better help message with commands description
 * __PING__ - check the connection. Will ask also for authentication
 * __S, s__ - subscribe to some query. Will start sending the results to the console JID ("bot.console")
 * __N, n__ - subscribe to notify. TODO: announce the notify results only when ask for them
 * __UN, un, U, u__ - unsubscribe from ALL subscriptions

Make sure you have the correct settings for your bot JID and password ("bot.jid" and "bot.password")
and for the account, that will receive all messages ("bot.console")

    require 'collecta_bot'

    class SearchBot < Collecta::Bot
        def self.format_result(msg, debug = true)
            # some fancy message formatting
            ...
        end
    end

    SearchBot.run("config.yml")
    

### Desktop notifications (Growl, libnotify) 

_collecta_notifyio.rb_

Desktop notifications via http://notify.io/ service are also available. You can use the original 
[Growl client for Mac](http://www.notify.io/download/notifyio-client.py) or
my [python-notify based client for Linux](http://github.com/zh/wip/blob/master/python/notifyio-notify.py).

Be sure to adjust _notifyio.userhash_ and _notifyio.apikey_ in the config file. You can get their values from
the [notify.io settings page](http://www.notify.io/dashboard/settings).

You need to supply the search query via the command line parameter:

    $ ruby ./collecta_notifyio.rb "iphone category:story"


## ToDo

 * ruby gem
 * patched switchboard for command line parameters usage ( _--query iphone --notify "apple,mac"_ )
