
require 'open3'

module IcingaCertService

  module Executor

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

#         while line = stdout_err.gets
#           puts line
#         end

        returnValue = wait_thr.value
#        stdOut      = stdout_err.read
#
#        unless returnValue.success?
#          logger.error( '------------------------------------')
#          logger.error( returnValue )
#          logger.error( cmd )
#          logger.error( '------------------------------------')
#          abort 'FAILED !!!'
#        end
#
#        logger.debug( returnValue )
#
#        if( returnValue == 0 ) # && !stdOut.to_s.empty? )
#          logger.debug( stdOut )
#        else
#
#        end
#

        result = {
          :exit    => returnValue.success?,
          :message => stdout_err.gets
        }

      end

      return result

    end

  end

end
