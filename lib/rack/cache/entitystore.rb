require 'digest/sha1'

module Rack::Cache
  # Entity stores are used to cache response bodies across requests. All
  # Implementations are required to calculate a SHA checksum of the data written
  # which becomes the response body's key.
  class EntityStore

    # Read body calculating the SHA1 checksum and size while
    # yielding each chunk to the block. If the body responds to close,
    # call it after iteration is complete. Return a two-tuple of the form:
    # [ hexdigest, size ].
    def slurp(body)
      digest, size = Digest::SHA1.new, 0
      body.each do |part|
        size += part.length
        digest << part
        yield part
      end
      body.close if body.respond_to? :close
      [ digest.hexdigest, size ]
    end

    private :slurp


    # Stores entity bodies on the heap using a Hash object.
    class Heap < EntityStore

      # Create the store with the specified backing Hash.
      def initialize(hash={})
        @hash = hash
      end

      # Determine whether the response body with the specified key (SHA1)
      # exists in the store.
      def exist?(key)
        @hash.include?(key)
      end

      # Return an object suitable for use as a Rack response body for the
      # specified key.
      def open(key)
        (body = @hash[key]) && body.dup
      end

      # Read all data associated with the given key and return as a single
      # String.
      def read(key)
        (body = @hash[key]) && body.join
      end

      # Write the Rack response body immediately and return the SHA1 key.
      def write(body)
        buf = []
        key, size = slurp(body) { |part| buf << part }
        @hash[key] = buf
        [key, size]
      end

      def self.resolve(uri)
        new
      end
    end

    HEAP = Heap
    MEM  = Heap

    # Stores entity bodies on disk at the specified path.
    class Disk < EntityStore

      # Path where entities should be stored. This directory is
      # created the first time the store is instansiated if it does not
      # already exist.
      attr_reader :root

      def initialize(root)
        @root = root
        FileUtils.mkdir_p root, :mode => 0755
      end

      def exist?(key)
        File.exist?(body_path(key))
      end

      def read(key)
        File.read(body_path(key))
      rescue Errno::ENOENT
        nil
      end

      # Open the entity body and return an IO object. The IO object's
      # each method is overridden to read 8K chunks instead of lines.
      def open(key)
        io = File.open(body_path(key), 'rb')
        def io.each
          while part = read(8192)
            yield part
          end
        end
        io
      rescue Errno::ENOENT
        nil
      end

      def write(body)
        filename = ['buf', $$, Thread.current.object_id].join('-')
        temp_file = storage_path(filename)
        key, size =
          File.open(temp_file, 'wb') { |dest|
            slurp(body) { |part| dest.write(part) }
          }

        path = body_path(key)
        if File.exist?(path)
          File.unlink temp_file
        else
          FileUtils.mkdir_p File.dirname(path), :mode => 0755
          FileUtils.mv temp_file, path
        end
        [key, size]
      end

    protected
      def storage_path(stem)
        File.join root, stem
      end

      def spread(key)
        key = key.dup
        key[2,0] = '/'
        key
      end

      def body_path(key)
        storage_path spread(key)
      end

      def self.resolve(uri)
        path = File.expand_path(uri.opaque || uri.path)
        new path
      end
    end

    DISK = Disk
    FILE = Disk

    # Stores entity bodies in memcached.
    class MemCache < EntityStore

      # The underlying Memcached instance used to communicate with the
      # memcahced daemon.
      attr_reader :cache

      def initialize(server="localhost:11211", options={})
        @cache =
          if server.respond_to?(:stats)
            server
          else
            require 'memcached'
            Memcached.new(server, options)
          end
      end

      def exist?(key)
        cache.append(key, '')
        true
      rescue Memcached::NotStored
        false
      end

      def read(key)
        cache.get(key, false)
      rescue Memcached::NotFound
        nil
      end

      def open(key)
        if data = read(key)
          [data]
        else
          nil
        end
      end

      def write(body)
        buf = StringIO.new
        key, size = slurp(body){|part| buf.write(part) }
        cache.set(key, buf.string, 0, false)
        [key, size]
      end

      extend Rack::Utils

      # Create MemCache store for the given URI. The URI must specify
      # a host and may specify a port, namespace, and options:
      #
      # memcached://example.com:11211/namespace?opt1=val1&opt2=val2
      #
      # Query parameter names and values are documented with the memcached
      # library: http://tinyurl.com/4upqnd
      def self.resolve(uri)
        server = "#{uri.host}:#{uri.port || '11211'}"
        options = parse_query(uri.query)
        options.keys.each do |key|
          value =
            case value = options.delete(key)
            when 'true' ; true
            when 'false' ; false
            else value.to_sym
            end
          options[k.to_sym] = value
        end
        options[:namespace] = uri.path.sub(/^\//, '')
        new server, options
      end
    end

    MEMCACHE = MemCache
    MEMCACHED = MemCache

  end

end
