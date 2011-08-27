Redis Registration Agent
------------------------

A plugin to store data from the RegistrationMetaData plugin in Redis. It has
the same intentiion as the MongoDB Registration Agent available at
http://projects.puppetlabs.com/projects/mcollective-plugins/wiki/AgentRegistrationMongoDB

WARNING!!! This is Alpha software

Installation
------------

- The RegistrationMetaData registration plugin and Registration should be setup
- A running redis server on one node, there this agent is supposed to run
- The redis and yaml rubygems

Configuration
-------------

- mcollective/server.conf

<pre>
  plugin.registration.redis_host = 127.0.0.1
  plugin.registration.redis_port = 6379
  plugin.registration.config = /etc/mcollective/registration.yaml
</pre>

- /etc/mcollective/registration.yaml

See example in Git
