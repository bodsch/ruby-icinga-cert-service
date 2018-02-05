
require 'logger'

# -------------------------------------------------------------------------------------------------

module Logging

  # global function to use the logger instance
  #
  def logger
    @logger ||= Logging.logger_for( self.class.name )
  end

  # Use a hash class-ivar to cache a unique Logger per class:
  @loggers = {}

  class << self

    # create an logger instance for classname
    #
    def logger_for( classname )
      @loggers[classname] ||= configure_logger_for( classname )
    end

    # configure the logger
    #
    def configure_logger_for( classname )

      log_level = ENV.fetch('LOG_LEVEL', 'DEBUG' )
      level = log_level.dup

      # DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
      log_level = case level.upcase
        when 'DEBUG'
          Logger::DEBUG   # Low-level information for developers.
        when 'INFO'
          Logger::INFO    # Generic (useful) information about system operation.
        when 'WARN'
          Logger::WARN    # A warning.
        when 'ERROR'
          Logger::ERROR   # A handleable error condition.
        when 'FATAL'
          Logger::FATAL   # An unhandleable error that results in a program crash.
        else
          Logger::UNKNOWN # An unknown message that should always be logged.
        end

      $stdout.sync           = true
      logger                 = Logger.new($stdout)
      logger.level           = log_level
      logger.datetime_format = '%Y-%m-%d %H:%M:%S %z'
      logger.formatter       = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime( logger.datetime_format )}] #{severity.ljust(5)}  #{msg}\n"
      end

      logger
    end
  end
end

# -------------------------------------------------------------------------------------------------
