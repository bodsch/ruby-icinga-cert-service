
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
    def save( id, data )

      @storage ||= {}
      @storage[id] ||= {}
      @storage[id] = data

    end

    # get data
    #
    # @param [String, #read]
    #
    def findById( id )

      if( @storage != nil )

        entities = @storage.dig(id) || {}
      else
        return {}
      end
    end

    # get all data
    #
    def entries()

      return  @storage
    end

  end
end

