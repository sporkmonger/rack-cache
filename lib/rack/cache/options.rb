require 'rack'
require 'rack/cache/storage'

module Rack::Cache
  # Configuration options and utility methods for option access. Rack::Cache
  # uses the Rack Environment to store option values. All options documented
  # below are stored in the Rack Environment as "rack-cache.<option>", where
  # <option> is the option name.
  #
  # The #set method can be used within an event or a top-level configuration
  # block to configure a option values. When #set is called at the top-level,
  # the value applies to all requests; when called from within an event, the
  # values applies only to the request being processed.

  module Options
    class << self
      private
      def option_accessor(key)
        define_method(key) { || read_option(key) }
        define_method("#{key}=") { |value| write_option(key, value) }
        define_method("#{key}?") { || !! read_option(key) }
      end
    end

    # Enable verbose trace logging. This option is currently enabled by
    # default but is likely to be disabled in a future release.
    option_accessor :verbose

    # The storage resolver. Defaults to the Rack::Cache.storage singleton instance
    # of Rack::Cache::Storage. This object is responsible for resolving metastore
    # and entitystore URIs to an implementation instances.
    option_accessor :storage

    # A URI specifying the meta-store implementation that should be used to store
    # request/response meta information. The following URIs schemes are
    # supported:
    #
    # * heap:/
    # * file:/absolute/path or file:relative/path
    # * memcached://localhost:11211[/namespace]
    #
    # If no meta store is specified the 'heap:/' store is assumed. This
    # implementation has significant draw-backs so explicit configuration is
    # recommended.
    option_accessor :metastore

    # A URI specifying the entity-store implement that should be used to store
    # response bodies. See the metastore option for information on supported URI
    # schemes.
    #
    # If no entity store is specified the 'heap:/' store is assumed. This
    # implementation has significant draw-backs so explicit configuration is
    # recommended.
    option_accessor :entitystore

    # The number of seconds that a cache entry should be considered
    # "fresh" when no explicit freshness information is provided in
    # a response. Explicit Cache-Control or Expires headers
    # override this value.
    #
    # Default: 0
    option_accessor :default_ttl

    # The underlying options Hash. During initialization (or outside of a
    # request), this is a default values Hash. During a request, this is the
    # Rack environment Hash. The default values Hash is merged in underneath
    # the Rack environment before each request is processed.
    def options
      @env || @default_options
    end

    # Set multiple options.
    def options=(hash={})
      hash.each { |key,value| write_option(key, value) }
    end

    # Set an option. When +option+ is a Symbol, it is set in the Rack
    # Environment as "rack-cache.option". When +option+ is a String, it
    # exactly as specified. The +option+ argument may also be a Hash in
    # which case each key/value pair is merged into the environment as if
    # the #set method were called on each.
    def set(option, value=self)
      if value == self
        self.options = option.to_hash
      else
        write_option option, value
      end
    end

  private
    def read_option(key)
      options[option_name(key)]
    end

    def write_option(key, value)
      options[option_name(key)] = value
    end

    def option_name(key)
      case key
      when Symbol ; "rack-cache.#{key}"
      when String ; key
      else raise ArgumentError
      end
    end

  private
    def initialize_options(options={})
      @default_options = {
        'rack-cache.verbose'     => true,
        'rack-cache.storage'     => Rack::Cache::Storage.instance,
        'rack-cache.metastore'   => 'heap:/',
        'rack-cache.entitystore' => 'heap:/',
        'rack-cache.default_ttl' => 0
      }
      self.options = options
    end
  end
end
