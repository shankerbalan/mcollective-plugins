# $Id$
#
# This is proof of concept code, please dont try it in production (yet)
# Acknowledgements
# https://github.com/puppetlabs/mcollective-plugins/tree/master/agent/registration-mongodb
# https://github.com/jamtur01/bunraku
#

module MCollective
  module Agent
    class Registration
      attr_reader :timeout, :meta

      def initialize
        @meta = {:license => "BSD",
          :author => "Shanker Balan <mail@shankerbalan.net>",
          :url    => "http://shankerbalan.net/"}

        require 'redis'

        @timeout = 2

        @config = Config.instance

        @redis_host  = @config.pluginconf["registration.redis_host"] || "127.0.0.1"
        @redis_port  = @config.pluginconf["registration.redis_port"] || 6379

        Log.instance.debug("Connecting to redisdb @ #{@redis_host}")

        @redis = Redis.new(:host => @redis_host, :port => @redis_port)
    end

    def handlemsg(msg, connection)
      senderid = msg[:senderid]
      req = msg[:body]

      if !req.kind_of?(Hash)
        Log.instance.info("recieved an invalid registration message from #{senderid}")
        return nil
      end

      fqdn        = req[:facts]["fqdn"]
      lastseen    = Time.now.to_i
      id          = @redis.incr(:node_counter)
      ttl         = 60 # seconds 

      # Sometimes facter doesnt send a fqdn?!
      if fqdn.nil?
        Log.instance.debug("Got stats without a FQDN in facts")
        return nil
      end

      @redis.multi do
        req[:facts].each { |key,val|
          Log.instance.debug("Setting #{fqdn}-#{id}:facts: #{key} => #{val}")
          @redis.hset("#{fqdn}-#{id}:facts", key, val)
          @redis.expire("#{fqdn}-#{id}:facts", ttl)
        }

        req[:agentlist].each { |agent|
          Log.instance.debug("Setting #{fqdn}-#{id}:agentlist => #{agent}")
          @redis.rpush("#{fqdn}-#{id}:agentlist", agent)
          @redis.expire("#{fqdn}-#{id}:agentlist", ttl)
        }

        req[:classes].each { |c|
          Log.instance.debug("Setting #{fqdn}-#{id}:classes => #{c}")
          @redis.rpush("#{fqdn}-#{id}:classes", c)
          @redis.expire("#{fqdn}-#{id}:classes", ttl)
        }

        Log.instance.info("Setting #{fqdn}-#{id}:lastseen => #{lastseen}")
        @redis.set("#{fqdn}-#{id}:lastseen", lastseen)
        @redis.expire("#{fqdn}-#{id}:lastseen", ttl)

        Log.instance.info("Setting #{fqdn}-#{id}:id => #{id}")
        @redis.sadd("all-nodes", fqdn)

        @redis.sadd("#{fqdn}", id)
      end

      nil
      end

      def help
      end
    end
  end
end

# vi:tabstop=2:expandtab:ai:filetype=ruby
