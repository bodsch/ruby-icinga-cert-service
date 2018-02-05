
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module Templates

    # write files based on a template
    #
    # @param [Hash, #read] params
    # @option params [String] :template
    # @option params [String] :destination_file
    # @option params [Hash] :environment
    #
    # @example
    #   write_template(
    #     template: 'templates/zones.d/endpoint.conf.erb',
    #     destination_file: file_name,
    #     environment: {
    #       host: host
    #     }
    #   )
    #
    #
    def write_template(params)

      template         = validate( params, required: true, var: 'template', type: String )
      destination_file = validate( params, required: true, var: 'destination_file', type: String )
      environment      = validate( params, required: true, var: 'environment', type: Hash )

      template = format( '%s/%s', @base_directory, template )

      return { status: 500, message: "template '#{template}' not found." } if( ! File.exist?(template) )

      begin
        template = ERB.new File.new(template).read
        date     = Time.now
        template = template.result( binding )

        begin
          logger.debug( "write to file: #{destination_file}" )
          file = File.open(destination_file, 'a')
          file.write(template)
        rescue => error
          logger.error(error.to_s)
          { status: 500, message: error.to_s }
        ensure
          file.close unless file.nil?
        end
      rescue => error
        logger.error(error.to_s)
        logger.debug( error.backtrace.join("\n") )

        { status: 500, message: error.to_s }
      end

      { status: 200, message: format('file \'%s\' has been created', destination_file) }

    end

  end
end
