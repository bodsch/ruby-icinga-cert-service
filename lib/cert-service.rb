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
    #
    # @example
    #    IcingaCertService::Client.new( icinga_master: 'icinga2-master.example.com' )
    #
    def initialize(params)

      @icinga_master = params.dig(:icinga_master)
      @tmp_directory = '/tmp/icinga-pki'

      @icinga_api_user = params.dig(:api, :user) || 'root'
      @icinga_api_password = params.dig(:api, :password) || 'icinga'

      version       = IcingaCertService::VERSION
      date          = '2018-01-08'
      detect_version

      logger.info('-----------------------------------------------------------------')
      logger.info(format(' certificate service for Icinga2 (%s)', @icinga_version))
      logger.info(format('  Version %s (%s)', version, date))
      logger.info('  Copyright 2017-2018 Bodo Schulz')
      logger.info('-----------------------------------------------------------------')
      logger.info('')
    end

    #
    #
    #
    #
    def detect_version

      max_retries  = 20
      sleep_between_retries = 8
      retried = 0

      @icinga_version = 'unknown'

      begin
        #response = rest_client.get( headers )
        response = RestClient::Request.execute(
          method: :get,
          url: format('https://%s:5665/v1/status/IcingaApplication', @icinga_master ),
          timeout: 5,
          headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
          user: @icinga_api_user,
          password: @icinga_api_password,
          verify_ssl: OpenSSL::SSL::VERIFY_NONE
        )

        response = response.body if(response.is_a?(RestClient::Response))
        response = JSON.parse(response) if(response.is_a?(String))
        results  = response.dig('results') if(response.is_a?(Hash))
        results  = results.first if(results.is_a?(Array))
        app_data = results.dig('status','icingaapplication','app')
        version  = app_data.dig('version') if(app_data.is_a?(Hash))

        if(version.is_a?(String))
          parts    = version.match(/^r(?<v>[0-9]+\.{0}\.[0-9]+)(.*)/i)
          @icinga_version = parts['v'].to_s.strip if(parts)
        end

      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        sleep( sleep_between_retries )
        retry
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
    end

    # function to read API Credentials from icinga2 Configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :api_user the API User, default is 'cert-service'
    #
    # @example
    #    read_api_credentials( api_user: 'admin' )
    #
    # @return [String, #read] the configured Password or nil
    #
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

    # add a host to 'api-users.conf'
    #
    # https://monitoring-portal.org/index.php?thread/41172-icinga2-api-mit-zertifikaten/&postID=251902#post251902
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    #
    # @example
    #    add_api_user( host: 'icinga2-satellite' )
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 204
    #  * :message [String] Message
    # @return nil if successful
    #
    def add_api_user(params)

      host = params.dig(:host)

      return { status: 500, message: 'no hostname to create an api user' } if( host.nil? )

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

        logger.debug(format('i miss an configuration for api user %s', host))

        File.open(file_name, 'a') do |f|
          f << "/*\n"
          f << " * generated at #{Time.now} with certificate service for Icinga2 #{IcingaCertService::VERSION}\n"
          f << " */\n"
          f << "object ApiUser \"#{host}\" {\n"
          f << "  client_cn = \"#{host}\"\n"
          f << "  permissions = [ \"*\" ]\n"
          f << "}\n\n"
        end

        return { status: 200, message: format('configuration for api user %s has been created', host) }
      end
    end

    # reload the icinga2-master using the api
    #
    # @param [Hash, #read] params
    #
    # @option params [String] :request
    #   * HTTP_X_API_USER
    #   * HTTP_X_API_PASSWORD
    #
    def reload_icinga_config(params)

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
