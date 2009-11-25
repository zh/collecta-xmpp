## Collecta XMPP API Ruby Library

Ruby library for easy working with the [Collecta XMPP API](http://developer.collecta.com/XmppApi/).

## Required gems and libraries

 * _xmpp4r_ - low level XMPP manipulations
 * _crack_ - XML parsing
 * _switchboard_ - only for collecta_jack.rb
 * _xmpp4-simple_ - only for collecta_bot.rb
 * _eventmachine_ - only for collecta_bot.rb
 * _sinatra_ - only for collecta_web.rb

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

### collecta_web.rb

 * _Collecta::App_ - Sinatra-based simple web API (inheriting _Sinatra::Default_)


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

_collecta\_notifyio.rb_

Desktop notifications via http://notify.io/ service are also available. You can use the original 
[Growl client for Mac](http://www.notify.io/download/notifyio-client.py) or
my [python-notify based client for Linux](http://github.com/zh/wip/blob/master/python/notifyio-notify.py).

Be sure to adjust _notifyio.userhash_ and _notifyio.apikey_ in the config file. You can get their values from
the [notify.io settings page](http://www.notify.io/dashboard/settings).

You need to supply the search query via the command line parameter:

    $ ruby ./collecta_notifyio.rb "iphone category:story"


### Simple web API (Sinatra application)

_collecta\_web.rb_

The API is not designed to be full featured web service. His primary goal is to be a backend for the main web service, 
deployed on Google AppEngine or Heroku. The main service need to take care for the users authentication and management,
saving queries per user etc. But because most of the deployment environments (GAE, Heroku etc.) cannot work with
XMPP PubSub, the current simple web API will be used for the real requests to the Collecta XMPP API.
The only protection in the moment is a secret _apikey_ parameter, send with each request. On the server side it must be setup
inside the _config.yml_ file like _web.apikey_ . For example:

    # --- config.yml
    ....
    web.apikey: SomeSecret
    bot.jid: bot@example.com
    ....

The API contains just two methods (POST requests): _/1/sub/_  and _/1/unsub_ for subscription to some query and unsubscription 
from all queries. Required parameters:

 * _apikey_ - _web.apikey_ from the _config.yml_ configuration file
 * _jid_ - JID on the account, that will recieve the results from the search
 * _q_ - Collecta query string

Starting the web API (it's Sinatra (means Rack) application) on _port 8080_:

    $ cd collecta-xmpp/
    $ rackup -p 8080

Example command-line usage:

    // me@jabber.org  will recieve results from the 'iphone'  and 'mac category:story' searches
    $ curl -X POST -d'apikey=secret' -d'jid=me@jabber.org' -d'q=iphone' http://example.com/1/sub/
    $ curl -X POST -d'apikey=secret' -d'jid=me@jabber.org' -d'q="mac category:story"' http://example.com/1/sub/
    // unsubscribe from all queries
    $  curl -X POST -d'apikey=secret' -d'jid=me@jabber.org' http://example.com/1/unsub/

The subscribed JID (_me@jabber.jp_ in the example above) need first to include the _"bot.jid"_ JID from the _config.yml_ file 
(_bot@example.com_ in _config.yml.dist_) in his roster and authorize it for messages exchange.

_collecta\_shell.rb_

Subscribing JIDs to some queries and unsubscription can be done also via a simple command-line shell. This application is independent
from the web API. They does not share their users subscriptions. In both application that relations are kept only in the memory. The
main web service need to take care for the saving of that relations.

Starting the shell:

    $ ruby ./collecta_shell.rb 
    > help
    "sub JID QUERY - subscribe JID to QUERY"
    "unsub JID     - unsubscribe JID"
    "exit          - exits the app"
    "help          - this help"
    >

Subscribe/unsubscribe some JID to/from a query:

    > sub me@jabber.org "iphone category:story"
    > unsub me@jabber.org
    > exit
    Finished
    $



## ToDo

 * ruby gem
 * patched switchboard for command line parameters usage ( _--query iphone --notify "apple,mac"_ )
