
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module ZoneHandler

    # add a satellite zone to 'zones.conf'
    #
    # @param [String] zone
    #
    # @example
    #    add_zone('icinga2-satellite')
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 200
    #  * :message [String] Message
    #
    # @return nil if successful
    #
    def add_zone( zone = nil )

      return { status: 500, message: 'no zone defined' } if zone.nil?

      zone_file =  '/etc/icinga2/zones.conf'

      if(File.exist?(zone_file))

        file     = File.open(zone_file, 'r')
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
        scan_zone = result.scan(/object Zone(.*)"(?<zone>.+\S)"/).flatten

        return { status: 200, message: format('the configuration for the zone %s already exists', zone) } if( scan_zone.include?(zone) == true )
      end

      logger.debug(format('i miss an configuration for zone \'%s\'', zone))

      begin
        result = write_template(
          template: 'templates/zones.conf.erb',
          destination_file: zone_file,
          environment: {
            zone: zone,
            icinga_master: @icinga_master
          }
        )
        # logger.debug(result)

      rescue => error
        logger.error(error.to_s)

        return { status: 500, message: error.to_s }
      end

      { status: 200, message: format('configuration for zone %s has been created', zone) }

    end

  end
end
