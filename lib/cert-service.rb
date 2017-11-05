#
#
#

require 'socket'
require 'open3'
require 'fileutils'

require_relative 'logging'
require_relative 'util'
require_relative 'cert-service/version'
require_relative 'cert-service/executor'
require_relative 'cert-service/certificate_handler'
require_relative 'cert-service/in-memory-cache'

# -----------------------------------------------------------------------------

class Time
  def add_minutes(m)
    self + (60 * m)
  end
end

# -----------------------------------------------------------------------------

#
#
#
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  class Client

    include Logging
    include Util::Tar
    include IcingaCertService::Executor
    include IcingaCertService::CertificateHandler
    include IcingaCertService::InMemoryDataCache

    # create a new instance
    #
    # @param [Hash, #read] params to configure the Client
    # @option params [String] :icinga_master The name (FQDN or IP) of the icinga2 master
    # @example
    #    IcingaCertService::Client.new( { :icinga_master => 'icinga2-master.example.com' } )
    def initialize(params = {})
      @icinga_master = params.dig(:icinga_master)
      @tmp_directory = '/tmp/icinga-pki'

      version       = IcingaCertService::VERSION
      date          = '2017-10-24'

      logger.info('-----------------------------------------------------------------')
      logger.info(' Icinga2 Cert Service')
      logger.info("  Version #{version} (#{date})")
      logger.info('  Copyright 2017 Bodo Schulz')
      logger.info('-----------------------------------------------------------------')
      logger.info('')
    end

    # function to read API Credentials from icinga2 Configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :api_user the API User, default is 'cert-service'
    # @example
    #    read_api_credentials( { :api_user => 'admin' } )
    # @return [String, #read] the configured Password or nil
    def read_api_credentials(params = {})

      api_user     = params.dig(:api_user) || 'cert-service'

      file_name    = '/etc/icinga2/conf.d/api-users.conf'

      file        = File.open(file_name, 'r')
      contents    = file.read
      password    = nil

      regexp_long = / # Match she-bang style C-comment
        \/\*          # Opening delimiter.
        [^*]*\*+      # {normal*} Zero or more non-*, one or more *
        (?:           # Begin {(special normal*)*} construct.
          [^*\/]      # {special} a non-*, non-\/ following star.
          [^*]*\*+    # More {normal*}
        )*            # Finish "Unrolling-the-Loop"
        \/            # Closing delimiter.
      /x

      regex       = /\"#{api_user}\"(.*){(.*)password(.*)=(.*)\"(?<password>.+[a-zA-Z0-9])\"(.*)}\n/m

      # remove comments
      result      = contents.gsub(regexp_long, '')

      # split our string into more parts
      result      = result.split('object ApiUser')

      # now, iterate over all blocks and get the password
      #
      result.each do |block|
        password = block.scan(regex)

        next unless password.is_a?(Array) && password.count == 1

        password = password.flatten.first
        break
      end

      password
    end

    # add a zone File to the icinga2-master configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    #
    # @example
    #    check_certificate( { :host => 'icinga2-satellite' } )
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 204
    #  * :message [String] Message
    # @return nil if successful
    def add_to_zone_file(params = {})
      host = params.dig(:host)

      if host.nil?

        return {
          status: 500,
          message: 'no host to add them in a icinga zone'
        }
      end

      FileUtils.mkpath('/etc/icinga2/automatic-zones.d') unless File.exist?('/etc/icinga2/automatic-zones.d')

      if File.exist?(format('/etc/icinga2/automatic-zones.d/%s.conf', host))
        return { status: 204, message: 'cert are created' }
      end

      file_name = format('/etc/icinga2/automatic-zones.d/%s.conf', host)

      if( File.exist?(file_name) )

        file     = File.open(file_name, 'r')
        contents = file.read

        regexp_long = / # Match she-bang style C-comment
          \/\*          # Opening delimiter.
          [^*]*\*+      # {normal*} Zero or more non-*, one or more *
          (?:           # Begin {(special normal*)*} construct.
            [^*\/]      # {special} a non-*, non-\/ following star.
            [^*]*\*+    # More {normal*}
          )*            # Finish "Unrolling-the-Loop"
          \/            # Closing delimiter.
        /x
        result = contents.gsub(regexp_long, '')

        scan_endpoint = result.scan(/object Endpoint(.*)"(?<endpoint>.+\S)"/).flatten
        scan_zone     = result.scan(/object Zone(.*)"(?<zone>.+\S)"/).flatten

        if( scan_endpoint.include?(host) && scan_zone.include?(host) )
          logger.debug('nothing to do')
        else

          if( scan_endpoint.include?(host) == false )

            logger.debug('missing endpoint')

            File.open(file_name, 'a') do |f|
              f << "/*\n"
              f << " * generated at #{Time.now} with IcingaCertService\n"
              f << " */\n"
              f << "object Endpoint \"#{host}\" {\n"
              f << "}\n\n"
            end
          end

          if( scan_zone.include?(host) == false )

            logger.debug('missing zone')

            File.open(file_name, 'a') do |f|
              f << "object Zone \"#{host}\" {\n"
              f << "  endpoints = [ \"#{host}\" ]\n"
              f << "  parent = ZoneName\n"
              f << "}\n\n"
            end
          end

        end
      else

        File.open(file_name, 'a') do |f|
          f << "/*\n"
          f << " * generated at #{Time.now} with IcingaCertService\n"
          f << " */\n"
          f << "object Endpoint \"#{host}\" {\n"
          f << "}\n\n"
          f << "object Zone \"#{host}\" {\n"
          f << "  endpoints = [ \"#{host}\" ]\n"
          f << "  parent = ZoneName\n"
          f << "}\n\n"
        end

      end
    end

    # TODO
    # add to api-users.conf
    # https://monitoring-portal.org/index.php?thread/41172-icinga2-api-mit-zertifikaten/&postID=251902#post251902
    def add_api_user(params = {})

      host = params.dig(:host)

      if( host.nil? )
        return { status: 500, message: 'no host to add them in a api user' }
      end

      file_name = '/etc/icinga2/conf.d/api-users.conf'

      unless( File.exist?(file_name) )
        return { status: 500, message: format( 'api user not successful configured! file %s missing', file_name ) }
      end

      file     = File.open(file_name, 'r')
      contents = file.read

      regexp_long = / # Match she-bang style C-comment
        \/\*          # Opening delimiter.
        [^*]*\*+      # {normal*} Zero or more non-*, one or more *
        (?:           # Begin {(special normal*)*} construct.
          [^*\/]      # {special} a non-*, non-\/ following star.
          [^*]*\*+    # More {normal*}
        )*            # Finish "Unrolling-the-Loop"
        \/            # Closing delimiter.
      /x
      result = contents.gsub(regexp_long, '')

      scan_api_user     = result.scan(/object ApiUser(.*)"(?<zone>.+\S)"/).flatten

      if( scan_api_user.include?(host) == false )

        logger.debug('missing apiuser')

        File.open(file_name, 'a') do |f|
          f << "object ApiUser \"#{host}\" {\n"
          f << "  client_cn = \"#{host}\"\n"
          f << "  permissions = [ \"*\" ]\n"
          f << "}\n\n"
        end
      end

    end

    # reload the icinga2-master configuration
    #
    # call the system 'service' tool or 'supervisorctl' if this used
    def reload_icinga_config
      # check init system
      # /usr/sbin/service
      # /usr/bin/supervisord

      command = nil

      command = '/usr/bin/supervisorctl reload icinga2' if File.exist?('/usr/bin/supervisorctl')
      command = '/usr/sbin/service icinga2 reload' if File.exist?('/usr/sbin/service')
      command = '/bin/s6-svc -u /etc/s6/icinga2' if File.exist?('/bin/s6-svc')

      if( command.nil? )
        { status: 500,  message: 'unknown service for an restart detected.' }
      end

      result      = exec_command( cmd: command )

      exit_code    = result.dig(:code)
      exit_message = result.dig(:message)

      if( exit_code != true )
        logger.error(format('command \'%s\'', command))
        logger.error(format('returned with exit-code %d', exit_code))
        logger.error(exit_message)

        abort 'FAILED !!!'
      end

      { status: 200, message: 'service restarted' }
    end
  end
end
