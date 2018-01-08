#
#
#

require 'socket'
require 'open3'
require 'fileutils'
require 'rest-client'


require_relative 'logging'
require_relative 'util'
require_relative 'cert-service/version'
require_relative 'cert-service/executor'
require_relative 'cert-service/certificate_handler'
require_relative 'cert-service/endpoint_handler'
require_relative 'cert-service/zone_handler'
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
    include IcingaCertService::EndpointHandler
    include IcingaCertService::ZoneHandler
    include IcingaCertService::InMemoryDataCache

    attr_accessor :icinga_version

    # create a new instance
    #
    # @param [Hash, #read] params to configure the Client
    # @option params [String] :icinga_master The name (FQDN or IP) of the icinga2 master
    # @example
    #    IcingaCertService::Client.new( { :icinga_master => 'icinga2-master.example.com' } )
    def initialize(params = {})

      @icinga_master = params.dig(:icinga_master)
      @tmp_directory = '/tmp/icinga-pki'

      @icinga_api_user = params.dig(:api, :user) || 'root'
      @icinga_api_password = params.dig(:api, :password) || 'icinga'

      version       = IcingaCertService::VERSION
      date          = '2018-01-06'
      detect_version

      logger.info('-----------------------------------------------------------------')
      logger.info(format(' Icinga2 Cert Service for Icinga %s', @icinga_version))
      logger.info(format('  Version %s (%s)', version, date))
      logger.info('  Copyright 2017-2018 Bodo Schulz')
      logger.info('-----------------------------------------------------------------')
      logger.info('')

      #@icinga2 = Icinga2.new( config )
    end

    #
    #
    #
    #
    def detect_version

      # TODO
      # use the API!
      # curl -k -s -u root:icinga -H 'Accept: application/json' -X POST 'https://localhost:5665/v1/actions/restart-process'
      api_user     = @icinga_api_user
      api_password = @icinga_api_password
      max_retries  = 20
      sleep_between_retries = 8
      retried = 0

      @icinga_version = 'unknown'

      options = { user: api_user, password: api_password, verify_ssl: OpenSSL::SSL::VERIFY_NONE }
      headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      url     = format('https://%s:5665/v1/status/IcingaApplication', @icinga_master )

      rest_client = RestClient::Resource.new( URI.encode( url ), options )

      begin
        response = rest_client.get( headers )

        return nil if( response.nil? )
        return nil unless(response.is_a?(Hash))

        app_data = response.dig('icingaapplication','app')

        # version and revision
        @icinga_version, @revision = parse_version(app_data.dig('version'))
        #   - node_name
        @node_name = app_data.dig('node_name')
        #   - start_time
        @start_time = Time.at(app_data.dig('program_start').to_f)

      rescue RestClient::ExceptionWithResponse => e

          if( retried < max_retries )
            retried += 1
            logger.debug( format( 'connection refused (retry %d / %d)', retried, max_retries ) )
            sleep( sleep_between_retries )
            retry
          else
            raise format( 'Maximum retries (%d) reached. Giving up ...', max_retries )
          end
      end
#       command = '/usr/sbin/icinga2 --version'
#
#       result       = exec_command(cmd: command)
#       exit_code    = result.dig(:code)
#       exit_message = result.dig(:message)
#
#       @icinga_version = 'unknown' if( exit_code == 1 )
#
#       parts = exit_message.match(/^icinga2(.*)version: r(?<v>[0-9]+\.{0}\.[0-9]+)(.*)/i)
#
#       @icinga_version = parts['v'].to_s.strip if(parts)
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

    # add to api-users.conf
    #
    # https://monitoring-portal.org/index.php?thread/41172-icinga2-api-mit-zertifikaten/&postID=251902#post251902
    #
    def add_api_user(params = {})

      host = params.dig(:host)

      return { status: 500, message: 'no host to add them in a api user' } if( host.nil? )

      file_name = '/etc/icinga2/conf.d/api-users.conf'

      return { status: 500, message: format( 'api user not successful configured! file %s missing', file_name ) } unless( File.exist?(file_name) )

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

        logger.debug(format('i miss an ApiUser configuration for %s', host))

        File.open(file_name, 'a') do |f|
          f << "object ApiUser \"#{host}\" {\n"
          f << "  client_cn = \"#{host}\"\n"
          f << "  permissions = [ \"*\" ]\n"
          f << "}\n\n"
        end
      end

    end

    # reload the icinga2-master using the api
    #
    # @param [Hash, #read] params
    # @option params [String] :request
    #   * HTTP_X_API_USER
    #   * HTTP_X_API_PASSWORD
    #
    def reload_icinga_config(params = {})

      # TODO
      # use the API!
      # curl -k -s -u root:icinga -H 'Accept: application/json' -X POST 'https://localhost:5665/v1/actions/restart-process'
      api_user     = params.dig(:request, 'HTTP_X_API_USER')
      api_password = params.dig(:request, 'HTTP_X_API_PASSWORD')

      return { status: 500, message: 'missing API Credentials - API_USER' } if( api_user.nil?)
      return { status: 500, message: 'missing API Credentials - API_PASSWORD' } if( api_password.nil? )

      password = read_api_credentials( api_user: api_user )

      return { status: 500, message: 'wrong API Credentials' } if( password.nil? || api_password != password )

      options = { user: api_user, password: api_password, verify_ssl: OpenSSL::SSL::VERIFY_NONE }
      headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      url     = format('https://%s:5665/v1/actions/restart-process', @icinga_master )

      rest_client = RestClient::Resource.new( URI.encode( url ), options )

      begin
        response = rest_client.post( {}.to_json, headers )

      rescue RestClient::ExceptionWithResponse => e

        logger.error("Error: restart-process has failed: '#{e}'")
        logger.error(JSON.pretty_generate(params))

        return { status: 500, message: e }
      end

      { status: 200, message: 'service restarted' }
    end
  end
end
