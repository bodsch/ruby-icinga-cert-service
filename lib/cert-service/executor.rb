
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
    def exec_command(params = {})
      cmd = params.dig(:cmd)

      if cmd.nil?

        return {
          exit: 1,
          message: 'no command found'
        }
      end

      logger.debug(cmd)

      result = {}

      Open3.popen2(cmd) do |_stdin, stdout_err, wait_thr|
        return_value = wait_thr.value

        result = {
          exit: return_value.success?,
          message: stdout_err.gets
        }
      end

      result
    end
  end
end
