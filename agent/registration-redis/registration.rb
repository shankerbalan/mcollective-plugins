# $Id$
#
# This is proof of concept code, please dont try it in production (yet)
# Acknowledgements
# https://github.com/puppetlabs/mcollective-plugins/tree/master/agent/registration-mongodb
# https://github.com/jamtur01/bunraku
#

# Basic rules:
# - Only update if there is a change
# Schema:
# all-nodes => [ fqdns ]
# fqdn => [ timestamps ]
#   - fqdn-timestamp:facts = facts{}
#   - fqdn-timestamp:agentlist = []
#   - fqdn-timestamp:classes = []
#   - fqdn-timestamp:lastseen = string

module MCollective
  module Agent
    class Registration
      attr_reader :timeout, :meta

      def initialize
        @meta = {:license => "BSD",
          :author => "Shanker Balan <mail@shankerbalan.net>",
          :url    => "http://shankerbalan.net/"}

        require 'redis'
        require 'yaml'

        @timeout = 2

        @config = Config.instance

        @redis_host  = @config.pluginconf["registration.redis_host"] || "127.0.0.1"
        @redis_port  = @config.pluginconf["registration.redis_port"] || 6379
        @config_file = @config.pluginconf["registration.config"] || "/etc/mcollective/registration.yaml"

        Log.instance.debug("Connecting to redisdb @ #{@redis_host}")

        @redis = Redis.new(:host => @redis_host, :port => @redis_port)

        @yaml = YAML.load_file(@config_file)
    end

    def handlemsg(msg, connection)
      senderid = msg[:senderid]
      req = msg[:body]

      if !req.kind_of?(Hash)
        Log.instance.info("recieved an invalid registration message from #{senderid}")
        return nil
      end

      fqdn     = req[:facts]["fqdn"]
      lastseen = Time.now.to_i

      # Sometimes fact doesnt send a fqdn?!
      if fqdn.nil?
        Log.instance.info("Got stats without a FQDN in facts from #{senderid}: #{req}")
        return nil
      end

      # did we get a unique id?
      if id.nil?
        Log.instance.info("Skipping update for #{fqdn}. Failed to get unique id")
        return nil
      end

      Log.instance.debug("Received valid registration update from sender #{senderid} at #{lastseen}")

      tmp_ttl = 300
      # tmp keys
      fqdn_tmp            = fqdn + "-tmp"
      fqdn_tmp_facts      = fqdn_tmp + ":facts"
      fqdn_tmp_classes    = fqdn_tmp + ":classes"
      fqdn_tmp_agentlist  = fqdn_tmp + ":agentlist"
      fqdn_tmp_lastseen   = fqdn_tmp + ":lastseen"

      @redis.sadd("all-nodes", fqdn)

      # create the tmp store
      @redis.multi do
        # del all
        @redis.del(fqdn_tmp_facts, fqdn_tmp_classes, fqdn_tmp_agentlist, fqdn_tmp_lastseen)

        if @yaml["facts"]["enabled"] == 1
          skip = @yaml["facts"]["skip"]
          req[:facts].each { |key,val|
            if skip[key] == 1
              #Log.instance.debug("Skipping fact #{key}")
              next
            else
              @redis.hset(fqdn_tmp_facts, key, val)
              @redis.expire(fqdn_tmp_facts, tmp_ttl)
            end
          }
          Log.instance.debug("Updated #{fqdn_tmp_facts} with ttl #{tmp_ttl}")
        end

        if @yaml["classes"]["enabled"] == 1
          req[:classes].each { |c|
            @redis.rpush(fqdn_tmp_classes, c)
            @redis.expire(fqdn_tmp_classes, tmp_ttl)
          }
          Log.instance.debug("Updated #{fqdn_tmp_classes} with ttl #{tmp_ttl}")
        end

        if @yaml["agentlist"]["enabled"] == 1
          req[:agentlist].each { |agent|
            @redis.rpush(fqdn_tmp_agentlist, agent)
            @redis.expire(fqdn_tmp_agentlist, tmp_ttl)
          }
          Log.instance.debug("Updated #{fqdn_tmp_agentlist} with ttl #{tmp_ttl}")
        end

        @redis.set(fqdn_tmp_lastseen, lastseen)
      end

      # last
      needupdate = 0
      last                  = @redis.sort(fqdn).pop.to_i

      if last > 0
        Log.instance.debug("#{fqdn}: last #{last}")
        fqdn_last             = fqdn + "-" + last.to_s
        fqdn_last_facts       = fqdn_last + ":facts"
        fqdn_last_classes     = fqdn_last + ":classes"
        fqdn_last_agentlist   = fqdn_last + ":agentlist"
        fqdn_last_lastseen    = fqdn_last + ":lastseen"

        # do diff
        tmp_facts   = @redis.hvals(fqdn_tmp_facts)
        last_facts  = @redis.hvals(fqdn_last_facts)
        diff_facts  = tmp_facts - last_facts

        unless diff_facts.any?
          Log.instance.info("#{fqdn}: No updated needed")
        else
          Log.instance.debug("#{fqdn}: facts need updating (#{diff_facts})")
          needupdate = 1
        end
      else
        Log.instance.info("#{fqdn}: no recent entry found. Creating new one")
      end

      if needupdate > 0
        fqdn_new            = fqdn + "-" + lastseen.to_s
        fqdn_new_facts      = fqdn_new + ":facts"
        fqdn_new_classes    = fqdn_new + ":classes"
        fqdn_new_agentlist  = fqdn_new + ":agentlist"
        fqdn_new_lastseen   = fqdn_new + ":lastseen"

        # move tmp to new with id as timestamp (lastseen)
        @redis.multi do
          @redis.rename(fqdn_tmp_facts,     fqdn_new_facts)
          @redis.rename(fqdn_tmp_classes,   fqdn_new_classes)
          @redis.rename(fqdn_tmp_agentlist, fqdn_new_agentlist)
          @redis.rename(fqdn_tmp_lastseen,  fqdn_new_lastseen)
          @redis.sadd(fqdn, lastseen)
          Log.instance.debug("#{fqdn_tmp} moved to #{fqdn_new}")
        end
      end

      nil
      end

      def help
      end
    end
  end
end

# vi:tabstop=2:expandtab:ai:filetype=ruby
