require 'redis'
require 'redis/distributed'
require 'yaml'

# This class is for managing Redis database configurations
# using config/redis.yml. 
#
# If multiple hosts are defined, it will generate you a DistRedis,
# otherwise you get a Redis object, both defined in the redis-rb rubygem

class RedisFactory  
  class << self
    def gimme(prefix='')
      config = current_config(prefix)
      
      if config[:hosts].is_a? Array
        
        # TODO: loop through hosts array, passing each host and the database id to a build-url method, instantiate Redis::Distributed with those options
        
        host_urls = config[:hosts].map{|host| build_uri(host, config[:database]) }
        
        Redis::Distributed.new(host_urls)
      else
        Redis.new(config)
      end
    end
    
    def current_config(prefix)
      prefix = prefix.to_s
      
      # In redis.yml you can specify different servers for the various environments. We use the
      # current environment to select the configuration, ie: development, production, or test.
      #
      # When running from Rails, or a Rails rake task, then we get the environment from Rails.env
      # and everybody is happy.
      #
      # However, we also execute this file from the resque-web Sinatra app, which does not have
      # Rails.env defined. In that case, we first check the RAILS_ENV environmental variable, and
      # finally we default to "development" to make it easier to run locally.
      #
      # Regarding using RAILS_ENV, that's a bit weird for a Sinatra app, but it keeps the
      # commands consistent across all the various services in the deployment.
      rails_env = Rails.env rescue ENV['RAILS_ENV'] || "development"
      
      config_key = if prefix.empty?
                    rails_env
                  else
                    prefix.chomp('_') + '_' + rails_env
                  end
      
      config = configurations[config_key]
      
      if config
        
        # This is config.symbolize_keys! but sometimes we want to be able to use this before Rails is loaded
        config.keys.each do |key|
          config[(key.to_sym rescue key) || key] = config.delete(key)
        end        
        
      else
        raise "Could not find a Redis configuration for '#{config_key}', please doublecheck config/redis.yml"
      end
     
      config[:db] ||= config[:database]
     
      config
    end
    
    def configurations
      root = Rails.root rescue File.join( File.dirname(__FILE__), '..' ) # Allows RedisFactory to be used outside a Rails project
      
      @@configurations ||= YAML.load_file( File.join(root, 'config', 'redis.yml') )
    end
    
    # This is only used in testing. Don't use it for real
    def configurations=(config_hash)
      @@configurations = config_hash
    end
    
    def build_uri(host_port, database)
      "redis://#{host_port}/#{database}"
    end
    
  end
end