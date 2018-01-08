
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module EndpointHandler

    # add a zone File to the icinga2-master configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    #
    # @example
    #    add_endpoint( { :host => 'icinga2-satellite' } )
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 204
    #  * :message [String] Message
    # @return nil if successful
    def add_endpoint(params = {})

      host = params.dig(:host)

      return { status: 500, message: 'no host to add them in a icinga zone' } if host.nil?

      # add the zone object
      add_zone( host )

      zone_directory = format('/etc/icinga2/zones.d/%s', host)
      file_name      = format('%s/%s.conf', zone_directory, host)

      FileUtils.mkpath(zone_directory) unless File.exist?(zone_directory)

      return { status: 204, message: 'endpoint already created' } if File.exist?(file_name)

#      FileUtils.mkpath('/etc/icinga2/automatic-zones.d') unless File.exist?('/etc/icinga2/automatic-zones.d')
#      return { status: 204, message: 'cert are created' } if File.exist?(format('/etc/icinga2/automatic-zones.d/%s.conf', host))
#      file_name = format('/etc/icinga2/automatic-zones.d/%s.conf', host)

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
#         scan_zone     = result.scan(/object Zone(.*)"(?<zone>.+\S)"/).flatten

        return { status: 200, message: format('the Endpoint configuration for %s exists', host) } if( scan_endpoint.include?(host) == true )
      end

        logger.debug(format('i miss an Endpoint configuration for %s', host))

        File.open(file_name, 'a') do |f|
          f << "/*\n"
          f << " * generated at #{Time.now} with certificate service for Icinga2 #{IcingaCertService::VERSION}\n"
          f << " */\n"
          f << "object Endpoint \"#{host}\" {\n"
          f << "}\n\n"
        end

#         if( scan_endpoint.include?(host) && scan_zone.include?(host) )
#           logger.debug('nothing to do')
#         else
#
#           if( scan_endpoint.include?(host) == false )
#
#             logger.debug(format('i miss an Endpoint configuration for %s', host))
#
#             File.open(file_name, 'a') do |f|
#               f << "/*\n"
#               f << " * generated at #{Time.now} with IcingaCertService\n"
#               f << " */\n"
#               f << "object Endpoint \"#{host}\" {\n"
#               f << "}\n\n"
#             end
#           end
#
# #           if( scan_zone.include?(host) == false )
# #
# #             logger.debug(format('i miss an Zone configuration for %s', host))
# #
# #             File.open(file_name, 'a') do |f|
# #               f << "object Zone \"#{host}\" {\n"
# #               f << "  endpoints = [ \"#{host}\" ]\n"
# #               f << "  parent = \"master\"\n"
# #               f << "}\n\n"
# #             end
# #           end
#
#         end
#       else
#
#         File.open(file_name, 'a') do |f|
#           f << "/*\n"
#           f << " * generated at #{Time.now} with IcingaCertService\n"
#           f << " */\n"
#           f << "object Endpoint \"#{host}\" {\n"
#           f << "}\n\n"
#           f << "/* object Zone \"#{host}\" {\n"
#           f << "  endpoints = [ \"#{host}\" ]\n"
#           f << "  parent = \"master\"\n"
#           f << "} */ \n\n"
#         end
#
#      end

    end
  end
end
