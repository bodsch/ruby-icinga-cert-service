#!/usr/bin/ruby
#
# 05.10.2016 - Bodo Schulz
#
#
# v2.1.0

# -----------------------------------------------------------------------------

require 'sinatra/base'
require 'sinatra/basic_auth'
require 'json'
require 'yaml'

require_relative '../lib/cert-service'
require_relative '../lib/logging'

# -----------------------------------------------------------------------------

module Sinatra

  class CertServiceRest < Base

    register Sinatra::BasicAuth

    include Logging

    icinga2Master = ENV['ICINGA_MASTER']   ? ENV['ICINGA_MASTER']   : nil
    basicAuthUser = ENV['BASIC_AUTH_USER'] ? ENV['BASIC_AUTH_USER'] : 'admin'
    basicAuthPass = ENV['BASIC_AUTH_PASS'] ? ENV['BASIC_AUTH_PASS'] : 'admin'

    configure do

      set :environment, :production

      # default configuration
      @logDirectory     = '/tmp/log'
      @cacheDir         = '/tmp/cache'

      @restServicePort  = 4567
      @restServiceBind  = '0.0.0.0'

      if( File.exist?( '/etc/cm-monitoring.yaml' ) )

        config = YAML.load_file( '/etc/cm-monitoring.yaml' )

        @logDirectory     = config['logDirectory']         ? config['logDirectory']         : '/tmp'
        @restServicePort  = config['rest-service']['port'] ? config['rest-service']['port'] : 4567
        @restServiceBind  = config['rest-service']['bind'] ? config['rest-service']['bind'] : '0.0.0.0'

      else
        puts "no configuration exists, use default settings"
      end

    end

    set :logging, true
    set :app_file, caller_files.first || $0
    set :run, Proc.new { $0 == app_file }
    set :dump_errors, true
    set :show_exceptions, true
    set :public_folder, '/var/www/'

    set :bind, @restServiceBind
    set :port, @restServicePort.to_i

    # -----------------------------------------------------------------------------

    error do
      msg = "ERROR\n\nThe cert-rest-service has nasty error - " + env['sinatra.error']

      msg.message
    end

    # -----------------------------------------------------------------------------

    before do
      content_type :json
    end

    before '/v2/*/:host' do
      request.body.rewind
      @request_paylod = request.body.read
    end

    # -----------------------------------------------------------------------------

    # configure Basic Auth
    authorize "API" do |username, password|
      username == basicAuthUser && password == basicAuthPass
    end

    # -----------------------------------------------------------------------------

    config = {
      :icingaMaster => icinga2Master
    }

    ics = IcingaCertService::Client.new( config )

    # curl \
    #  -u "foo:bar" \
    #  --request GET \
    #  --header "X-API-USER: cert-service" \
    #  --header "X-API-KEY: knockknock" \
    #  --output /tmp/$HOST-NAME.tgz \
    #  http://$REST-SERVICE:4567/v2/request/$HOST-NAME
    #
    protect "API" do

      get '/v2/request/:host' do

        certResult   = ics.createCert( { :host => params[:host], :request => request.env } )
        resultStatus = certResult.dig(:status).to_i

        status resultStatus

        JSON.pretty_generate( certResult ) + "\n"

      end
    end


    # curl \
    #  -u "foo:bar" \
    #  --request POST \
    #  http://$REST-SERVICE:4567/v2/ticket/$HOST-NAME
    #
    protect "API" do

      post '/v2/ticket/:host' do

        status 200

        result = ics.createTicket( { :host => params[:host] } )

        JSON.pretty_generate( result ) + "\n"

      end
    end


    # curl \
    #  -u "foo:bar" \
    #  --request GET \
    #  --header "X-API-USER: cert-service" \
    #  --header "X-API-KEY: knockknock" \
    #  --header "X-CHECKSUM: ${checksum}" \
    #  --output /tmp/$HOST-NAME.tgz \
    #  http://$REST-SERVICE:4567/v2/cert/$HOST-NAME
    #
    protect "API" do

      get '/v2/cert/:host' do

        host   = params[:host]

        result = ics.checkCert( { :host => params[:host], :request => request.env } )

        logger.debug( result )

        resultStatus = result.dig(:status).to_i

        if( resultStatus == 200 )

          path     = result.dig(:path)
          fileName = result.dig(:fileName)

          status resultStatus

          send_file( sprintf( '%s/%s', path, fileName ), :filename => fileName, :type => 'Application/octet-stream' )
        else

          status resultStatus

          JSON.pretty_generate( result ) + "\n"
        end

      end
    end



    not_found do
      jj = {
        'meta' => {
            'code' => 404,
            'message' => 'Request not found.'
        }
      }
      content_type :json
      JSON.pretty_generate(jj)
    end



    # -----------------------------------------------------------------------------
    run! if app_file == $0
    # -----------------------------------------------------------------------------
  end

end

