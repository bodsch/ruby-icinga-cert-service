
require 'open3'

module IcingaCertService

  module Executor

    # execute system commands with a Open3.popen2() call
    #
    # @param [Hash, #read] params
    # @option params [String] :cmd
    #
    # @return [Hash, #read]
    #  * :exit [Integer] Exit-Code
    #  * :message [String] Message
    def execCommand( params = {} )

      cmd = params.dig(:cmd)

      if( cmd == nil )

        return {
          :exit    => 1,
          :message => 'no command found'
        }
      end

      logger.debug( cmd )

      result = Hash.new()

      Open3.popen2( cmd ) do |stdin, stdout_err, wait_thr|

        returnValue = wait_thr.value

        result = {
          :exit    => returnValue.success?,
          :message => stdout_err.gets
        }

      end

      return result

    end

  end

end
