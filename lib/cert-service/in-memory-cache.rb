
module IcingaCertService

  # small in-memory Cache
  #
  module InMemoryDataCache
    # create a new Instance
    def initialize
      @storage = {}
    end

    # save data
    #
    # @param [String, #read] id
    # @param [misc, #read] data
    #
    def save(id, data)
      @storage ||= {}
      @storage[id] ||= {}
      @storage[id] = data
    end

    # get data
    #
    # @param [String, #read]
    #
    def find_by_id(id)
      if( !@storage.nil? )
        @storage.dig(id) || {}
      else
        {}
      end
    end

    # get all data
    #
    def entries
      @storage
    end
  end
end


module JobQueue

  class Job

    def initialize
      @jobs  = MiniCache::Store.new()
    end

    def cacheKey( params = {} )
      Digest::MD5.hexdigest( Hash[params.sort].to_s )
    end

    def add( params = {} )
      checksum = cacheKey(params)
      @jobs.set( checksum ) { MiniCache::Data.new( 'true' ) } if( self.jobs( params ) == false )
    end


    def del( params = {} )
      checksum = cacheKey(params)
      @jobs.unset( checksum )
    end


    def jobs( params = {} )
      checksum = cacheKey(params)
      current  = @jobs.get( checksum )
      # no entry found
      return false if( current.nil? )
      return true
    end
  end
end

