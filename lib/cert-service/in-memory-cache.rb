
module IcingaCertService

  module InMemoryDataCache

    def initialize
      @storage = {}
    end

    def save( id, data )

      @storage ||= {}
      @storage[id] ||= {}
      @storage[id] = data

    end

    def findById( id )

      if( @storage != nil )

        entities = @storage.dig(id) || {}
      else
        return {}
      end
    end

    def entries()

      return  @storage
    end

  end
end

