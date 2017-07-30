
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
      date          = '2017-07-06'

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

    # create a certificate
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    # @example
    #    create_certificate( { :host => 'icinga2-satellite', :request => { 'HTTP_X_API_USER' => 'admin', 'HTTP_X_API_KEY' => 'admin' } } )
    # @return [Hash, #read]
    #  * :status [Integer] 200 for successful, or 500 for an error
    #  * :master_name [String] the Name of the Icinga2-master (need to configure the satellite correctly)
    #  * :master_ip [String] the IP of the Icinga2-master (need to configure the satellite correctly)
    #  * :checksum [String] a created Checksum to retrive the certificat archive
    #  * :timestamp [Integer] a timestamp for the created archive
    #  * :timeout [Integer] the timeout for the created archive
    #  * :file_name [String] the archive Name
    #  * :path [String] the Path who stored the certificate archive
    def create_certificate(params = {})
      host      = params.dig(:host)
      api_user  = params.dig(:request, 'HTTP_X_API_USER')
      api_key   = params.dig(:request, 'HTTP_X_API_KEY')

      if host.nil?

        return {
          status: 500,
          message: 'no hostname'
        }
      end

      if api_user.nil? || api_key.nil?

        return {
          status: 500,
          message: 'missing API Credentials'
        }
      end

      password = read_api_credentials(api_user: api_user)

      if password.nil? || api_key != password

        return {
          status: 500,
          message: 'wrong API Credentials'
        }
      end

      if @icinga_master.nil?

        begin
          server_name = Socket.gethostbyname(Socket.gethostname).first
        rescue => e
          logger.error(e)

          server_name = @icinga_master
        else
          server_ip    = IPSocket.getaddress(Socket.gethostname)
        end
      else
        server_name = @icinga_master

        begin
          server_ip    = IPSocket.getaddress(server_name)
        rescue => e
          logger.error(server_name)
          logger.error(e)

          server_ip = '127.0.0.1'
        end
      end

      pki_base_directory = '/etc/icinga2/pki'

      pki_master_key = format('%s/%s.key', pki_base_directory, server_name)
      pki_master_csr = format('%s/%s.csr', pki_base_directory, server_name)
      pki_master_crt = format('%s/%s.crt', pki_base_directory, server_name)
      pki_master_ca  = format('%s/ca.crt', pki_base_directory)

      unless File.exist?(pki_base_directory)

        return {
          status: 500,
          message: 'no PKI directory found. Please configure first the Icinga2 Master!'
        }
      end

      FileUtils.mkpath('/etc/icinga2/zone.d/global-templates')
      FileUtils.mkpath(format('/etc/icinga2/zone.d/%s', host))

      #
      unless File.exist?('/etc/icinga2/zone.d/global-templates/services.conf')

        FileUtils.mv('/etc/icinga2/conf.d/services.conf', '/etc/icinga2/zone.d/global-templates/services.conf')
      end

      logger.debug(format('search PKI files for the Master \'%s\'', server_name))

      if !File.exist?(pki_master_key) || !File.exist?(pki_master_csr) || !File.exist?(pki_master_crt)

        logger.error('missing file')

        logger.debug(pki_master_key)
        logger.debug(pki_master_csr)
        logger.debug(pki_master_crt)

        return {
          status: 500,
          message: format('missing PKI for Icinga2 Master \'%s\'', server_name)
        }
      end

      tmp_host_directory = format('%s/%s', @tmp_directory, host)
      # uid         = File.stat('/etc/icinga2/conf.d').uid
      # gid         = File.stat('/etc/icinga2/conf.d').gid

      FileUtils.mkpath(tmp_host_directory) unless File.exist?(tmp_host_directory)

      if File.exist?(tmp_host_directory)
        #         FileUtils.chown_R( uid, gid, @tmp_directory )
        FileUtils.chmod_R(0o777, @tmp_directory)
      end

      unless File.exist?(tmp_host_directory)

        return {
          status: 500,
          message: 'can\'t create temporary directory'
        }

      end

      salt = Digest::SHA256.hexdigest(host)

      pki_satellite_key = format('%s/%s.key', tmp_host_directory, host)
      pki_satellite_csr = format('%s/%s.csr', tmp_host_directory, host)
      pki_satellite_crt = format('%s/%s.crt', tmp_host_directory, host)
      pki_ticket       = '%PKI_TICKET%'

      commands = []

      commands << format('icinga2 pki new-cert --cn %s --key %s --csr %s', host, pki_satellite_key, pki_satellite_csr)
      commands << format('icinga2 pki sign-csr --csr %s --cert %s', pki_satellite_csr, pki_satellite_crt)
      commands << format('icinga2 pki save-cert --key %s --cert %s --trustedcert %s/trusted-master.crt --host %s', pki_satellite_key, pki_satellite_crt, tmp_host_directory, server_name)
      commands << format('icinga2 pki ticket --cn %s --salt %s', server_name, salt)
      commands << format('icinga2 pki request --host %s --port 5665 --ticket %s --key %s --cert %s --trustedcert %s/trusted-master.crt --ca %s', server_name, pki_ticket, pki_satellite_key, pki_satellite_crt, tmp_host_directory, pki_master_ca)

      pki_ticket = nil
      next_command = nil

      commands.each_with_index do |c, index|
        next_command = commands[index + 1]

        result      = exec_command(cmd: c)

        exit_code    = result.dig(:exit)
        exit_message = result.dig(:message)

        if exit_code != true
          logger.error(format('command \'%s\'', c))
          logger.error(format('returned with exit-code %s', exit_code))
          logger.error(exit_message)

          return {
            status: 500,
            message: format('Internal Error: cmd %s, exit code %s', c, exit_code)
          }
        end

        if exit_message =~ /information\//

          # logger.debug( 'no ticket' )
        else

          pki_ticket = exit_message.strip

          next_command = next_command.gsub!('%PKI_TICKET%', pki_ticket)

        end
      end

      FileUtils.cp(pki_master_ca, format('%s/ca.crt', tmp_host_directory))

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
      save(checksum, timestamp: timestamp, timeout: timeout, host: host)

      # remove the temporars data
      FileUtils.rm_rf(tmp_host_directory)

      add_to_zone_file(params)
      add_api_user(params)
      reload_icinga_config

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

    # create a icinga2 Ticket
    # (NOT USED YET)
    #
    def create_ticket(params = {})
      host = params.dig(:host)

      if host.nil?
        logger.error('no hostname')

        return {
          status: 500,
          message: 'no hostname'
        }
      end

      server_name  = Socket.gethostbyname(Socket.gethostname).first
      server_ip    = IPSocket.getaddress(Socket.gethostname)

      logger.debug(host)

      file_name = '/etc/icinga2/constants.conf'

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

      logger.debug(result)

      ticket_salt   = result.scan(/const TicketSalt(.*)=(.*)"(?<ticketsalt>.+\S)"/).flatten
      host_ticket   = nil

      if ticket_salt.to_s != ''

        logger.debug(format(' ticket Salt : %s', ticket_salt))

      else

        o      = [('a'..'z'), ('A'..'Z'), (0..9)].map(&:to_a).flatten
        string = (0...50).map { o[rand(o.length)] }.join

        ticket_salt = Digest::SHA256.hexdigest(string)

        File.write(file_name, text.gsub(/const TicketSalt = ""/, "const TicketSalt = \"#{ticket_salt}\""))
      end

      commands = []

      commands << format('icinga2 pki ticket --cn %s --salt %s', host, ticket_salt)

      commands.each_with_index do |c, _index|
        result      = exec_command(cmd: c)

        exit_code    = result.dig(:exit)
        exit_message = result.dig(:message)

        if exit_code != true
          logger.error(format('command \'%s\'', c))
          logger.error(format('returned with exit-code %d', exit_code))
          logger.error(exit_message)

          abort 'FAILED !!!'
        end

        host_ticket = exit_message
        logger.debug(host_ticket)
      end

      timestamp = Time.now

      {
        status: 200,
        master_name: server_name,
        master_ip: server_ip,
        ticket: host_ticket,
        timestamp: timestamp.to_i
      }
    end

    # check the certificate Data
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    #
    # @example
    #    check_certificate( { :host => 'icinga2-satellite', :request => { 'HTTP_X_CHECKSUM' => '000000000000000000000000000000000000' } } )
    #
    # @return [Hash, #read] for an error:
    #  * :status [Integer] 404 or 500
    #  * :message [String] Error Message
    # @return [Hash, #read] for succesfuly:
    #  * :status [Integer] 200
    #  * :file_name [String] Filename
    #  * :path [String]
    def check_certificate(params = {})
      host     = params.dig(:host)
      checksum = params.dig(:request, 'HTTP_X_CHECKSUM')

      if host.nil? || checksum.nil?

        logger.debug(JSON.pretty_generate(params.dig(:request)))

        return {
          status: 500,
          message: 'no valid data to get the certificate'
        }
      end

      file = format('%s/%s.tgz', @tmp_directory, host)

      if File.exist?(file)

        in_memory_data      = find_by_id(checksum)

        generated_timestamp = in_memory_data.dig(:timestamp)
        generated_timeout   = in_memory_data.dig(:timeout)

        if generated_timeout.nil?

          generated_timestamp  = File.mtime(file)
          generated_timeout    = File.mtime(file).add_minutes(10)
        end

        logger.debug(generated_timestamp)
        logger.debug(generated_timeout)

        check_timestamp = Time.now

        logger.debug(format(' generated timestamp : %s', generated_timestamp.to_datetime.strftime('%d-%m-%Y %H:%M:%S')))
        logger.debug(format(' generated timeout   : %s', generated_timeout.to_datetime.strftime('%d-%m-%Y %H:%M:%S')))
        logger.debug(format(' check     timeout   : %s', check_timestamp.to_datetime.strftime('%d-%m-%Y %H:%M:%S')))

        logger.debug(format(' diff                : %s', (generated_timeout.to_i - check_timestamp.to_i)))

        if check_timestamp.to_i > generated_timeout.to_i

          return {
            status: 404,
            message: 'timed out. please ask for an new cert'
          }
        end

        add_to_zone_file(params)
        reload_icinga_config

        return {
          status: 200,
          file_name: format('%s.tgz', host),
          path: @tmp_directory
        }
      else

        return {
          status: 404,
          message: 'file dosnt exits'
        }

      end
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

      unless File.exist?('/etc/icinga2/automatic-zones.d')

        FileUtils.mkpath('/etc/icinga2/automatic-zones.d')
      end

      if File.exist?(format('/etc/icinga2/automatic-zones.d/%s.conf', host))

        return {
          status: 204,
          message: 'cert are created'
        }
      end

      file_name = format('/etc/icinga2/automatic-zones.d/%s.conf', host)

      if !File.exist?(file_name)

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

      else

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

        if scan_endpoint.include?(host) && scan_zone.include?(host)

          logger.debug('nothing to do')
        else

          if scan_endpoint.include?(host) == false

            logger.debug('missing endpoint')

            File.open(file_name, 'a') do |f|
              f << "/*\n"
              f << " * generated at #{Time.now} with IcingaCertService\n"
              f << " */\n"
              f << "object Endpoint \"#{host}\" {\n"
              f << "}\n\n"
            end
          end

          if scan_zone.include?(host) == false

            logger.debug('missing zone')

            File.open(file_name, 'a') do |f|
              f << "object Zone \"#{host}\" {\n"
              f << "  endpoints = [ \"#{host}\" ]\n"
              f << "  parent = ZoneName\n"
              f << "}\n\n"
            end
          end

        end

      end
    end

    # TODO
    # add to api-users.conf
    # https://monitoring-portal.org/index.php?thread/41172-icinga2-api-mit-zertifikaten/&postID=251902#post251902
    def add_api_user(params = {})
      host = params.dig(:host)

      if host.nil?

        return {
          status: 500,
          message: 'no host to add them in a api user'
        }
      end

      file_name = '/etc/icinga2/conf.d/api-users.conf'

      if File.exist?(file_name)

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

        if scan_api_user.include?(host)

          logger.debug('nothing to do')
        else

          logger.debug('missing apiuser')

          File.open(file_name, 'a') do |f|
            f << "object ApiUser \"#{host}\" {\n"
            f << "  client_cn = \"#{host}\"\n"
            f << "  permissions = [ \"*\" ]\n"
            f << "}\n\n"
          end
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

      if File.exist?('/usr/bin/supervisorctl')
        command = '/usr/bin/supervisorctl reload icinga2'
      end

      if File.exist?('/usr/sbin/service')
        command = '/usr/sbin/service icinga2 reload'
      end

      if File.exist?('/bin/s6-svc')
        command = '/bin/s6-svc -xd /etc/s6/icinga2'
      end

      unless command.nil?

        result      = exec_command(cmd: command)

        exit_code    = result.dig(:exit)
        exit_message = result.dig(:message)

        if exit_code != true
          logger.error(format('command \'%s\'', command))
          logger.error(format('returned with exit-code %d', exit_code))
          logger.error(exit_message)

          abort 'FAILED !!!'
        end

        return
      end
    end
  end
end
