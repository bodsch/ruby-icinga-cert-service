
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module EndpointHandler

    # add a Endpoint for distributed monitoring to the icinga2-master configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    #
    # @example
    #    add_endpoint( host: 'icinga2-satellite' )
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 204
    #  * :message [String] Message
    #
    # @return nil if successful
    #
    def add_endpoint(params)

      host      = validate( params, required: true, var: 'host', type: String )
      satellite = validate( params, required: false, var: 'satellite', type: Boolean ) || false

      return { status: 500, message: 'no hostname to create an endpoint' } if host.nil?

      # add the API user
      #
      add_api_user(params)

      # add the zone object
      #
      ret = add_zone(host)

      logger.debug( ret )

      if( satellite )
        file_name      = '/etc/icinga2/zones.conf'
      else
        zone_directory = format('/etc/icinga2/zones.d/%s', host)
        file_name      = format('%s/%s.conf', zone_directory, host)

        begin
          FileUtils.mkpath(zone_directory) unless File.exist?(zone_directory)
        rescue

        end
      end

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

        return { status: 200, message: format('the configuration for the endpoint %s already exists', host) } if( scan_endpoint.include?(host) == true )
      end

      logger.debug(format('i miss an configuration for endpoint \'%s\'', host))

#      current_dir = Dir.pwd
#      puts current_dir

      begin

        result = write_template(
          template: 'templates/zones.d/endpoint.conf.erb',
          destination_file: file_name,
          environment: {
            host: host
          }
        )

        create_backup

        logger.debug( result )
      rescue => error

        logger.debug(error)
      end

      { status: 200, message: format('configuration for endpoint \'%s\' has been created', host) }


#       raise 'hard exit'
#
#       begin
#         File.open(file_name, 'a') do |f|
#           f << "/*\n"
#           f << " * generated at #{Time.now} with certificate service for Icinga2 #{IcingaCertService::VERSION}\n"
#           f << " */\n"
#           f << "object Endpoint \"#{host}\" {}\n"
#         end
#
#         create_backup
#
#         { status: 200, message: format('configuration for endpoint %s has been created', host) }
#
#       rescue => error
#         { status: 404, message: error.to_s }
#       end
    end

  end
end
