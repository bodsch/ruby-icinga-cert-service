
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module ZoneHandler

    # add a satellite zone
    def add_zone(zone)

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

        return { status: 200, message: format('the Zone configuration for %s exists', zone) } if( scan_zone.include?(zone) == true )
      end

      logger.debug(format('i miss an Zone configuration for %s', zone))

      File.open(zone_file, 'a') do |f|
        f << "/*\n"
        f << " * generated at #{Time.now} with certificate service for Icinga2 #{IcingaCertService::VERSION}\n"
        f << " */\n"
        f << "object Zone \"#{zone}\" {\n"
        f << "  parent = \"#{@icinga_master}\"\n"
        f << "  endpoints = [ \"#{zone}\" ]\n"
        f << "}\n\n"
      end

    end

  end
end
