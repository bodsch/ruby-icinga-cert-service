
module IcingaCertService
  # Submodule for CertificateHandler
  #
  #
  module CertificateHandler

    # create a certificate
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    #
    # @example
    #    create_certificate( host: 'icinga2-satellite', request: { 'HTTP_X_API_USER => 'admin', HTTP_X_API_PASSWORD' => 'admin' } } )
    #
    # @return [Hash, #read]
    #  * :status [Integer] 200 for successful, or 500 for an error
    #  * :master_name [String] the Name of the Icinga2-master (need to configure the satellite correctly)
    #  * :master_ip [String] the IP of the Icinga2-master (need to configure the satellite correctly)
    #  * :checksum [String] a created Checksum to retrive the certificat archive
    #  * :timestamp [Integer] a timestamp for the created archive
    #  * :timeout [Integer] the timeout for the created archive
    #  * :file_name [String] the archive Name
    #  * :path [String] the Path who stored the certificate archive
    #
    def create_certificate( params )

      host         = params.dig(:host)
      api_user     = params.dig(:request, 'HTTP_X_API_USER')
      api_password = params.dig(:request, 'HTTP_X_API_PASSWORD')
      remote_addr  = params.dig(:request, 'REMOTE_ADDR')

      return { status: 500, message: 'no hostname' } if( host.nil? )
      return { status: 500, message: 'missing API Credentials - API_USER' } if( api_user.nil?)
      return { status: 500, message: 'missing API Credentials - API_PASSWORD' } if( api_password.nil? )

      password = read_api_credentials( api_user: api_user )

      return { status: 500, message: 'wrong API Credentials' } if( password.nil? || api_password != password )

      logger.info(format('got certificate request from %s', remote_addr))

      if( @icinga_master.nil? )
        begin
          server_name = icinga2_server_name
        rescue => e
          logger.error(e)
          server_name = @icinga_master
        else
          server_ip    = icinga2_server_ip
        end
      else
        server_name = @icinga_master
        begin
          server_ip    = icinga2_server_ip(server_name)
        rescue => e
          logger.error(server_name)
          logger.error(e)

          server_ip = '127.0.0.1'
        end
      end

      pki_base_directory = '/etc/icinga2/pki'
      pki_base_directory = '/var/lib/icinga2/certs' if( @icinga_version != '2.7' )

      return { status: 500, message: 'no PKI directory found. Please configure first the Icinga2 Master!' } if( pki_base_directory.nil? )

      pki_master_key = format('%s/%s.key', pki_base_directory, server_name)
      pki_master_csr = format('%s/%s.csr', pki_base_directory, server_name)
      pki_master_crt = format('%s/%s.crt', pki_base_directory, server_name)
      pki_master_ca  = format('%s/ca.crt', pki_base_directory)

      return { status: 500, message: 'no PKI directory found. Please configure first the Icinga2 Master!' } unless( File.exist?(pki_base_directory) )

      zone_base_directory = '/etc/icinga2/zone.d'

      FileUtils.mkpath( format('%s/global-templates', zone_base_directory) )
      FileUtils.mkpath( format('%s/%s', zone_base_directory, host) )

      #
      unless File.exist?(format('%s/global-templates/services.conf', zone_base_directory) )

        if( File.exist?('/etc/icinga2/conf.d/services.conf') )
          FileUtils.mv('/etc/icinga2/conf.d/services.conf', format('%s/global-templates/services.conf', zone_base_directory))
        else
          logger.error('missing services.conf under /etc/icinga2/conf.d')
        end
      end

      logger.debug(format('search PKI files for the Master \'%s\'', server_name))

      if( !File.exist?(pki_master_key) || !File.exist?(pki_master_csr) || !File.exist?(pki_master_crt) )
        logger.error('missing file')
        logger.debug(pki_master_key)
        logger.debug(pki_master_csr)
        logger.debug(pki_master_crt)

        return { status: 500, message: format('missing PKI for Icinga2 Master \'%s\'', server_name) }
      end

      tmp_host_directory = format('%s/%s', @tmp_directory, host)
      # uid         = File.stat('/etc/icinga2/conf.d').uid
      # gid         = File.stat('/etc/icinga2/conf.d').gid

      FileUtils.rmdir(tmp_host_directory) if(File.exist?(tmp_host_directory))
      FileUtils.mkpath(tmp_host_directory) unless File.exist?(tmp_host_directory)
      FileUtils.chmod_R(0o777, @tmp_directory) if File.exist?(tmp_host_directory)

      return { status: 500, message: 'can\'t create temporary directory' } unless File.exist?(tmp_host_directory)

      salt = Digest::SHA256.hexdigest(host)

      pki_satellite_key = format('%s/%s.key', tmp_host_directory, host)
      pki_satellite_csr = format('%s/%s.csr', tmp_host_directory, host)
      pki_satellite_crt = format('%s/%s.crt', tmp_host_directory, host)
      pki_ticket       = '%PKI_TICKET%'

      commands = []

      # icinga2 pki new-cert --cn $node --csr $node.csr --key $node.key
      # icinga2 pki sign-csr --csr $node.csr --cert $node.crt
      commands << format('icinga2 pki new-cert --cn %s --key %s --csr %s', host, pki_satellite_key, pki_satellite_csr)
      commands << format('icinga2 pki sign-csr --csr %s --cert %s', pki_satellite_csr, pki_satellite_crt)

      if( @icinga_version == '2.7' )
        commands << format('icinga2 pki save-cert --key %s --cert %s --trustedcert %s/trusted-master.crt --host %s', pki_satellite_key, pki_satellite_crt, tmp_host_directory, server_name)
        commands << format('icinga2 pki ticket --cn %s --salt %s', server_name, salt)
        commands << format('icinga2 pki request --host %s --port 5665 --ticket %s --key %s --cert %s --trustedcert %s/trusted-master.crt --ca %s', server_name, pki_ticket, pki_satellite_key, pki_satellite_crt, tmp_host_directory, pki_master_ca)
      end

      pki_ticket = nil
      next_command = nil

      commands.each_with_index do |c, index|

        next_command = commands[index + 1]
        result       = exec_command(cmd: c)
        exec_code    = result.dig(:code)
        exec_message = result.dig(:message)

        logger.debug( format( ' => %s', c ) )
        logger.debug( format( '    - [%s]  %s', exec_code, exec_message ) )

        if( exec_code != true )
          logger.error(exec_message)
          logger.error(format('  command \'%s\'', c))
          logger.error(format('  returned with exit-code \'%s\'', exec_code))

          return { status: 500, message: format('Internal Error: \'%s\' - \'cmd %s\'', exec_message, c) }
        end

        if( exec_message =~ %r{/information\//} )
          # logger.debug( 'no ticket' )
        else
          pki_ticket   = exec_message.strip
          next_command = next_command.gsub!('%PKI_TICKET%', pki_ticket) unless( next_command.nil? )
        end
      end

      FileUtils.cp( pki_master_ca, format('%s/ca.crt', tmp_host_directory) )

      #     # TODO
      # Build Checksum
      #       Dir[ sprintf( '%s/*', tmp_host_directory ) ].each do |file|
      #         if( File.directory?( file ) )
      #           next
      #         end
      #
      #         Digest::SHA2.hexdigest( File.read( file ) )
      #       end
      #

      # create TAR File
      io = tar(tmp_host_directory)
      # and compress
      gz = gzip(io)

      # write to filesystem

      archive_name = format('%s/%s.tgz', @tmp_directory, host)

      begin
        file = File.open(archive_name, 'w')

        file.binmode
        file.write(gz.read)
      rescue IOError => e
        # some error occur, dir not writable etc.
        logger.error(e)
      ensure
        file.close unless file.nil?
      end

      checksum  = Digest::SHA2.hexdigest(File.read(archive_name))
      timestamp = Time.now
      timeout   = timestamp.add_minutes(10)

      logger.debug(format(' timestamp : %s', timestamp.to_datetime.strftime('%d-%m-%Y %H:%M:%S')))
      logger.debug(format(' timeout   : %s', timeout.to_datetime.strftime('%d-%m-%Y %H:%M:%S')))

      # store datas in-memory
      #
      save(checksum, timestamp: timestamp, timeout: timeout, host: host)

      # remove the temporary data
      #
      FileUtils.rm_rf(tmp_host_directory)

      {
        status: 200,
        master_name: server_name,
        master_ip: server_ip,
        checksum: checksum,
        timestamp: timestamp.to_i,
        timeout: timeout.to_i,
        file_name: format('%s.tgz', host),
        path: @tmp_directory
      }
    end


    # check the certificate Data
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    #
    # @example
    #    check_certificate( host: 'icinga2-satellite', request: { 'HTTP_X_CHECKSUM' => '000000000000000000000000000000000000' } )
    #
    # @return [Hash, #read] for an error:
    #  * :status [Integer] 404 or 500
    #  * :message [String] Error Message
    #
    # @return [Hash, #read] for succesfuly:
    #  * :status [Integer] 200
    #  * :file_name [String] Filename
    #  * :path [String]
    #
    def check_certificate( params )

      host         = params.dig(:host)
      checksum     = params.dig(:request, 'HTTP_X_CHECKSUM')
      api_user     = params.dig(:request, 'HTTP_X_API_USER')
      api_password = params.dig(:request, 'HTTP_X_API_PASSWORD')
      remote_addr  = params.dig(:request, 'REMOTE_ADDR')

      return { status: 500, message: 'no valid data to get the certificate' } if( host.nil? || checksum.nil? )

      file = format('%s/%s.tgz', @tmp_directory, host)

      return { status: 404, message: 'file doesn\'t exits' } unless( File.exist?(file) )

      in_memory_data      = find_by_id(checksum)
      generated_timeout   = in_memory_data.dig(:timeout)
      generated_timeout   = File.mtime(file).add_minutes(10) if( generated_timeout.nil? )

      check_timestamp = Time.now

      return { status: 404, message: 'timed out. please ask for an new cert' } if( check_timestamp.to_i > generated_timeout.to_i )

      # add params to create the endpoint not in zones.d
      #
      params[:satellite] = true

      # add API User for this Endpoint
      #
      # add_api_user(params)

      # add Endpoint (and API User)
      # and create a backup of the generated files
      #
      add_endpoint(params)

      # restart service to activate the new certificate
      #
      # reload_icinga_config(params)

      { status: 200, file_name: format('%s.tgz', host), path: @tmp_directory }
    end


    # validate the CA against a checksum
    #
    # @param [Hash, #read] params
    # @option params [String] :checksum
    #
    def validate_certificate( params )

      checksum = params.dig(:checksum)

      return { status: 500, message: 'missing checksum' } if( checksum.nil? )

      pki_base_directory = '/var/lib/icinga2/ca'
      pki_master_ca  = format('%s/ca.crt', pki_base_directory)

      return { status: 500, message: 'no PKI directory found. Please configure first the Icinga2 Master!' } unless( File.exist?(pki_base_directory) )

      if( checksum.be_a_checksum )
        pki_master_ca_checksum = nil
        pki_master_ca_checksum = Digest::MD5.hexdigest(File.read(pki_master_ca)) if( checksum.produced_by(:md5) )
        pki_master_ca_checksum = Digest::SHA256.hexdigest(File.read(pki_master_ca)) if( checksum.produced_by(:sha256) )
        pki_master_ca_checksum = Digest::SHA384.hexdigest(File.read(pki_master_ca)) if( checksum.produced_by(:sha384) )
        pki_master_ca_checksum = Digest::SHA512.hexdigest(File.read(pki_master_ca)) if( checksum.produced_by(:sha512) )

        return { status: 500, message: 'wrong checksum type. only md5, sha256, sha384 and sha512 is supported' } if( pki_master_ca_checksum.nil? )
        return { status: 404, message: 'checksum not match.' } if( checksum != pki_master_ca_checksum )
        return { status: 200 }
      end

      { status: 500, message: 'checksum isn\'t a checksum' }
    end


    # sign a icinga2 satellite certificate with the new 2.8 pki feature
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    #
    # @example
    #    sign_certificate( host: 'icinga2-satellite', request: { 'HTTP_X_API_USER => 'admin', HTTP_X_API_PASSWORD' => 'admin' } } )
    #
    # @return [Hash, #read] for an error:
    #  * :status [Integer] 404 or 500
    #  * :message [String] Error Message
    #
    # @return [Hash, #read] for succesfuly:
    #  * :status [Integer] 200
    #  * :message [String]
    #  * :master_name [String]
    #  * :master_ip [String]
    #
    def sign_certificate( params )

      host          = params.dig(:host)
      api_user      = params.dig(:request, 'HTTP_X_API_USER')
      api_password  = params.dig(:request, 'HTTP_X_API_PASSWORD')
      remote_addr   = params.dig(:request, 'REMOTE_ADDR')
      real_ip       = params.dig(:request, 'HTTP_X_REAL_IP')
      forwarded_for = params.dig(:request, 'HTTP_X_FORWARDED_FOR')

      # logger.debug(params)

      logger.error('no hostname') if( host.nil? )
      logger.error('missing API Credentials - API_USER') if( api_user.nil? )
      logger.error('missing API Credentials - API_PASSWORD') if( api_password.nil? )

      return { status: 401, message: 'no hostname' } if( host.nil? )
      return { status: 401, message: 'missing API Credentials - API_USER' } if( api_user.nil?)
      return { status: 401, message: 'missing API Credentials - API_PASSWORD' } if( api_password.nil? )

      password = read_api_credentials( api_user: api_user )

      logger.error('wrong API Credentials') if( password.nil? || api_password != password )
      logger.error('wrong Icinga2 Version (the master required => 2.8)') if( @icinga_version == '2.7' )

      return { status: 401, message: 'wrong API Credentials' } if( password.nil? || api_password != password )
      return { status: 401, message: 'wrong Icinga2 Version (the master required => 2.8)' } if( @icinga_version == '2.7' )

      unless(remote_addr.nil? && real_ip.nil?)
        logger.info('we running behind a proxy')

        logger.debug("remote addr   #{remote_addr}")
        logger.debug("real ip       #{real_ip}")
        logger.debug("forwarded for #{forwarded_for}")

        remote_addr = forwarded_for
      end

      unless( remote_addr.nil? )
        host_short   = host.split('.')
        host_short   = if( host_short.count > 0 )
          host_short.first
        else
          host
        end

        remote_fqdn    = Resolv.getnames(remote_addr).sort.last
        remote_short   = remote_fqdn.split('.')
        remote_short   = if( remote_short.count > 0 )
          remote_short.first
        else
          remote_fqdn
        end

        logger.debug( "host_short   #{host_short}" )
        logger.debug( "remote_short #{remote_short}" )

        logger.error(format('This client (%s) cannot sign the certificate for %s', remote_fqdn, host ) ) unless( host_short == remote_short )

        return { status: 409, message: format('This client cannot sign the certificate for %s', host ) } unless( host_short == remote_short )
      end

      logger.info( format('sign certificate for %s', host) )

      # /etc/icinga2 # icinga2 ca list | grep icinga2-satellite-1.matrix.lan | sort -k2
      # e39c0b4bab4d0d9d5f97f0f54da875f0a60273b4fa3d3ef5d9be0d379e7a058b | Jan 10 04:27:38 2018 GMT | *      | CN = icinga2-satellite-1.matrix.lan
      # 5520324447b124a26107ded6d5e5b37d73e2cf2074bd2b5e9d8b860939f490df | Jan 10 04:51:38 2018 GMT |        | CN = icinga2-satellite-1.matrix.lan
      # 6775ea210c7559cf58093dbb151de1aaa3635950f696165eb4beca28487d193c | Jan 10 05:03:36 2018 GMT |        | CN = icinga2-satellite-1.matrix.lan

      commands = []
      commands << format('icinga2 ca list | grep %s | sort -k2 | tail -1', host) # sort by date

      commands.each_with_index do |c, index|

        result       = exec_command(cmd: c)
        exec_code    = result.dig(:code)
        exec_message = result.dig(:message)

        #logger.debug( "icinga2 ca list: '#{exec_message}'" )
        #logger.debug( "exit code: '#{exec_code}' (#{exec_code.class})" )

        return { status: 500, message: 'error to retrive the list of certificates with signing requests' } if( exec_code == false )

        regex = /^(?<ticket>.+\S) \|(?<date>.*)\|(.*)\| CN = (?<cn>.+\S)$/
        parts = exec_message.match(regex) if(exec_message.is_a?(String))

        logger.debug( "parts: #{parts} (#{parts.class})" )

        if(parts)
          ticket = parts['ticket'].to_s.strip
          date   = parts['date'].to_s.tr('GMT','').strip
          cn     = parts['cn'].to_s.strip

          result       = exec_command(cmd: format('icinga2 ca sign %s',ticket))
          exec_code    = result.dig(:code)
          exec_message = result.dig(:message)
          message      = exec_message.gsub('information/cli: ','')

          #logger.debug("exec code   : '#{exec_code}' (#{exec_code.class})" )
          logger.debug("exec message: '#{exec_message.strip}'")
          logger.debug("message     : '#{message.strip}'")

          # add 2hour to convert into CET (bad feeling)
          date_time = DateTime.parse(date).new_offset('+02:00')
          timestamp = date_time.to_time.to_i

          # create the endpoint and the reference zone
          # the endpoint are only after an reload available!
          #
          add_endpoint(params)

          return {
            status: 200,
            message: message,
            master_name: icinga2_server_name,
            master_ip: icinga2_server_ip,
            date: date_time.strftime("%Y-%m-%d %H:%M:%S"),
            timestamp: timestamp
          }

        else
          logger.error(format('i can\'t find a Ticket for host \'%s\'',host))
          logger.error( parts )

          return { status: 404, message: format('i can\'t find a Ticket for host \'%s\'',host) }
        end
      end

      { status: 204 }
    end
  end
end
