#!/usr/bin/ruby
#
#
#
#

require 'socket'
require 'open3'
require 'fileutils'

require_relative 'logging'
require_relative 'util'
require_relative 'cert-service/executor'
require_relative 'cert-service/in-memory-cache'

# -----------------------------------------------------------------------------

class Time
  def addMinutes(m)
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
    # @option params [String] :icingaMaster The name (FQDN or IP) of the icinga2 master
    # @example
    #    IcingaCertService::Client.new( { :icingaMaster => 'icinga2-master.example.com' } )
    def initialize( params = {} )

      @icingaMaster = params.dig( :icingaMaster )
      @tempDir      = '/tmp/icinga-pki'

      version       = '0.6.0-dev'
      date          = '2017-04-08'

      logger.info( '-----------------------------------------------------------------' )
      logger.info( ' Icinga2 Cert Service' )
      logger.info( "  Version #{version} (#{date})" )
      logger.info( '  Copyright 2017 Bodo Schulz' )
      logger.info( '-----------------------------------------------------------------' )
      logger.info( '' )

    end

    # function to read API Credentials from icinga2 Configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :apiUser the API User, default is 'cert-service'
    # @example
    #    readAPICredetials( { :apiUser => 'admin' } )
    # @return [String, #read] the configured Password or nil
    def readAPICredetials( params = {} )

      apiUser     = params.dig( :apiUser ) || 'cert-service'

      fileName    = '/etc/icinga2/conf.d/api-users.conf'

      file        = File.open( fileName, 'r' )
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

      regex       = /\"#{apiUser}\"(.*){(.*)password(.*)=(.*)\"(?<password>.+[a-zA-Z0-9])\"(.*)}\n/m

      # remove comments
      result      = contents.gsub( regexp_long, '' )

      # split our string into more parts
      result      = result.split( 'object ApiUser' )

      # now, iterate over all blocks and get the password
      #
      result.each do |block|

        password = block.scan( regex )

        if( password.is_a?( Array ) && password.count == 1 )

          password = password.flatten.first
          break
        end
      end

      return password
    end


    # create a certificate
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    # @example
    #    createCert( { :host => 'icinga2-satellite', :request => { 'HTTP_X_API_USER' => 'admin', 'HTTP_X_API_KEY' => 'admin' } } )
    # @return [Hash, #read]
    #  * :status [Integer] 200 for successful, or 500 for an error
    #  * :masterName [String] the Name of the Icinga2-master (need to configure the satellite correctly)
    #  * :masterIp [String] the IP of the Icinga2-master (need to configure the satellite correctly)
    #  * :checksum [String] a created Checksum to retrive the certificat archive
    #  * :timestamp [Integer] a timestamp for the created archive
    #  * :timeout [Integer] the timeout for the created archive
    #  * :fileName [String] the archive Name
    #  * :path [String] the Path who stored the certificate archive
    def createCert( params = {} )

      host     = params.dig( :host )
      apiUser  = params.dig( :request, 'HTTP_X_API_USER' )
      apiKey   = params.dig( :request, 'HTTP_X_API_KEY' )


      if( host == nil )

        return {
          :status  => 500,
          :message => 'no hostname'
        }
      end

      if(  apiUser == nil || apiKey == nil )

        return {
          :status  => 500,
          :message => 'missing API Credentials'
        }
      end

      password = self.readAPICredetials( { :apiUser => apiUser } )

      if( password == nil || apiKey != password )

        return {
          :status  => 500,
          :message => 'wrong API Credentials'
        }
      end


      if( @icingaMaster == nil )

        begin

          serverName  = Socket.gethostbyname( Socket.gethostname ).first
        rescue => e

          logger.error( e )

          serverName = @icingaMaster
        else
          serverIp    = IPSocket.getaddress( Socket.gethostname )
        end
      else
        serverName  = @icingaMaster

        begin
          serverIp    = IPSocket.getaddress( serverName )
        rescue =>  e

          logger.error( serverName )
          logger.error( e )

          serverIp    = '127.0.0.1'
        end
      end

      pkiBaseDirectory = '/etc/icinga2/pki'

      pkiMasterKEY = sprintf( '%s/%s.key', pkiBaseDirectory, serverName )
      pkiMasterCSR = sprintf( '%s/%s.csr', pkiBaseDirectory, serverName )
      pkiMasterCRT = sprintf( '%s/%s.crt', pkiBaseDirectory, serverName )
      pkiMasterCA  = sprintf( '%s/ca.crt', pkiBaseDirectory )

      if( !File.exist?( pkiBaseDirectory ) )

        return {
          :status  => 500,
          :message => 'no PKI directory found. Please configure first the Icinga2 Master!'
        }
      end

      FileUtils.mkpath( '/etc/icinga2/zone.d/global-templates' )
      FileUtils.mkpath( sprintf( '/etc/icinga2/zone.d/%s', host ) )

      #
      if( ! File.exists?( '/etc/icinga2/zone.d/global-templates/services.conf' ) )

        FileUtils.mv( '/etc/icinga2/conf.d/services.conf', '/etc/icinga2/zone.d/global-templates/services.conf' )
      end

      logger.debug( sprintf( 'search PKI files for the Master \'%s\'', serverName ) )

      if( !File.exist?( pkiMasterKEY ) || !File.exist?( pkiMasterCSR ) || !File.exist?( pkiMasterCRT ) )

        logger.error( 'missing file' )

        logger.debug( pkiMasterKEY )
        logger.debug( pkiMasterCSR )
        logger.debug( pkiMasterCRT )

        return {
          :status  => 500,
          :message => sprintf( 'missing PKI for Icinga2 Master \'%s\'', serverName )
        }
      end

      tempHostDir = sprintf( '%s/%s', @tempDir, host )
      uid         = File.stat( '/etc/icinga2/conf.d' ).uid
      gid         = File.stat( '/etc/icinga2/conf.d' ).gid

      logger.debug( uid )
      logger.debug( gid )

      if( ! File.exist?( tempHostDir ) )
        FileUtils.mkpath( tempHostDir )
      end

      if( File.exists?( tempHostDir ) )
#         FileUtils.chown_R( uid, gid, @tempDir )
        FileUtils.chmod_R( 0777, @tempDir )
      end

      if( ! File.exist?( tempHostDir ) )

        return {
          :status  => 500,
          :message => 'can\'t create temporary directory'
        }

      end

      salt = Digest::SHA256.hexdigest( host )

      pkiSatelliteKEY = sprintf( '%s/%s.key', tempHostDir, host )
      pkiSatelliteCSR = sprintf( '%s/%s.csr', tempHostDir, host )
      pkiSatelliteCRT = sprintf( '%s/%s.crt', tempHostDir, host )
      pkiTicket       = '%PKI_TICKET%'

      commands = Array.new()

      commands << sprintf( 'icinga2 pki new-cert --cn %s --key %s --csr %s', host, pkiSatelliteKEY, pkiSatelliteCSR )
      commands << sprintf( 'icinga2 pki sign-csr --csr %s --cert %s', pkiSatelliteCSR, pkiSatelliteCRT )
      commands << sprintf( 'icinga2 pki save-cert --key %s --cert %s --trustedcert %s/trusted-master.crt --host %s', pkiSatelliteKEY, pkiSatelliteCRT, tempHostDir, serverName )
      commands << sprintf( 'icinga2 pki ticket --cn %s --salt %s', serverName, salt )
      commands << sprintf( 'icinga2 pki request --host %s --port 5665 --ticket %s --key %s --cert %s --trustedcert %s/trusted-master.crt --ca %s', serverName, pkiTicket, pkiSatelliteKEY, pkiSatelliteCRT, tempHostDir, pkiMasterCA )

      pkiTicket   = nil

      commands.each_with_index { |c,index|

        nextCommand = commands[ index+1 ]

        result      = execCommand( { :cmd => c } )

        exitCode    = result.dig(:exit)
        exitMessage = result.dig(:message)

        if( exitCode != true )
          logger.error( sprintf( 'command \'%s\'', c ) )
          logger.error( sprintf( 'returned with exit-code %s', exitCode ) )
          logger.error( exitMessage )

          return {
            :status  => 500,
            :message => sprintf( 'Internal Error: cmd %s, exit code %s', c, exitCode )
          }
        end

        if( exitMessage =~ /information\// )

          #logger.debug( 'no ticket' )
        else

          pkiTicket = exitMessage.strip

          nextCommand = nextCommand.gsub!( '%PKI_TICKET%', pkiTicket)

        end
      }

      FileUtils.cp( pkiMasterCA, sprintf( '%s/ca.crt', tempHostDir ) )

#     # TODO
      # Build Checksum
#       Dir[ sprintf( '%s/*', tempHostDir ) ].each do |file|
#         if( File.directory?( file ) )
#           next
#         end
#
#         Digest::SHA2.hexdigest( File.read( file ) )
#       end
#

      # create TAR File
      io = tar( tempHostDir )
      # and compress
      gz = gzip( io )

      # write to filesystem

      archiveName = sprintf( '%s/%s.tgz', @tempDir, host )

      begin
        file = File.open( archiveName, 'w' )

        file.binmode()
        file.write( gz.read )

      rescue IOError => e
        #some error occur, dir not writable etc.
      ensure
        file.close unless file.nil?
      end

      checksum  = Digest::SHA2.hexdigest( File.read( archiveName ) )
      timestamp = Time.now()
      timeout   = timestamp.addMinutes( 10 )

      logger.debug( sprintf( ' timestamp : %s', timestamp.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )
      logger.debug( sprintf( ' timeout   : %s', timeout.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )

      # store datas in-memory
      save( checksum, { :timestamp => timestamp, :timeout => timeout, :host => host } )

      # remove the temporars data
      FileUtils.rm_rf( tempHostDir )

      result = self.addToZoneFile( params )
      result = self.reloadIcingaConfig()


      return {
        :status       => 200,
        :masterName   => serverName,
        :masterIp     => serverIp,
        :checksum     => checksum,
        :timestamp    => timestamp.to_i,
        :timeout      => timeout.to_i,
        :fileName     => sprintf( '%s.tgz', host ),
        :path         => @tempDir
      }

    end


    # create a icinga2 Ticket
    # (NOT USED YET)
    #
    def createTicket( params = {} )

      host = params.dig(:host)

      if( host == nil )
        logger.error( 'no hostname' )

        return {
          :status  => 500,
          :message => 'no hostname'
        }
      end

      serverName  = Socket.gethostbyname( Socket.gethostname ).first
      serverIp    = IPSocket.getaddress( Socket.gethostname )

      logger.debug( host )

      fileName = '/etc/icinga2/constants.conf'

      file     = File.open( fileName, 'r' )
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
      result = contents.gsub( regexp_long, '' )

      logger.debug( result )

      ticketSalt   = result.scan(/const TicketSalt(.*)=(.*)"(?<ticketsalt>.+\S)"/).flatten
      hostTicket   = nil

      if( ticketSalt.to_s != '' )

        logger.debug( sprintf( ' ticket Salt : %s', ticketSalt ) )

      else

        o      = [('a'..'z'), ('A'..'Z'), (0..9)].map(&:to_a).flatten
        string = (0...50).map { o[rand(o.length)] }.join

        ticketSalt = Digest::SHA256.hexdigest( string )

        File.write( fileName, text.gsub( /const TicketSalt = ""/, "const TicketSalt = \"#{ticketSalt}\"" ) )
      end


      commands = Array.new()

      commands << sprintf( 'icinga2 pki ticket --cn %s --salt %s', host, ticketSalt )


      commands.each_with_index { |c,index|

        result      = execCommand( { :cmd => c } )

        exitCode    = result.dig(:exit)
        exitMessage = result.dig(:message)

        if( exitCode != true )
          logger.error( sprintf( 'command \'%s\'', c ) )
          logger.error( sprintf( 'returned with exit-code %d', exitCode ) )
          logger.error( exitMessage )

          abort 'FAILED !!!'
        end

        hostTicket = exitMessage
        logger.debug( hostTicket )
      }

      timestamp = Time.now()

      return {
        :status      => 200,
        :masterName  => serverName,
        :masterIp    => serverIp,
        :ticket      => hostTicket,
        :timestamp   => timestamp.to_i
      }

    end


    # check the certificate Data
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    # @option params [Hash] :request
    #
    # @example
    #    checkCert( { :host => 'icinga2-satellite', :request => { 'HTTP_X_CHECKSUM' => '000000000000000000000000000000000000' } } )
    #
    # @return [Hash, #read] for an error:
    #  * :status [Integer] 404 or 500
    #  * :message [String] Error Message
    # @return [Hash, #read] for succesfuly:
    #  * :status [Integer] 200
    #  * :fileName [String] Filename
    #  * :path [String]
    def checkCert( params = {} )

      host     = params.dig( :host )
      checksum = params.dig( :request, 'HTTP_X_CHECKSUM' )

      if( host == nil || checksum == nil )

        logger.debug( JSON.pretty_generate( params.dig( :request ) ) )

        return {
          :status   => 500,
          :message  => 'no valid data to get the certificate'
        }
      end

      file = sprintf( '%s/%s.tgz', @tempDir, host )

      if( File.exist?( file ) )

        inMemoryData       = findById( checksum )

        generatedTimestamp = inMemoryData.dig(:timestamp)
        generatedTimeout   = inMemoryData.dig(:timeout)

        if( generatedTimeout == nil )

          generatedTimestamp  = File.mtime( file )
          generatedTimeout    = File.mtime( file ).addMinutes( 10 )
        end

        logger.debug( generatedTimestamp )
        logger.debug( generatedTimeout )

        checkTimestamp = Time.now()

        logger.debug( sprintf( ' generated timestamp : %s', generatedTimestamp.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )
        logger.debug( sprintf( ' generated timeout   : %s', generatedTimeout.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )
        logger.debug( sprintf( ' check     timeout   : %s', checkTimestamp.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )

        logger.debug( sprintf( ' diff                : %s', ( generatedTimeout.to_i - checkTimestamp.to_i ) ) )

        if( checkTimestamp.to_i > generatedTimeout.to_i )

          return {
            :status   => 404,
            :message  => 'timed out. please ask for an new cert'
          }
        end

        result = self.addToZoneFile( params )
        result = self.reloadIcingaConfig()

        return {
          :status    => 200,
          :fileName  => sprintf( '%s.tgz', host ),
          :path      => @tempDir
        }
      else

        return {
          :status   => 404,
          :message  => 'file dosnt exits'
        }

      end

    end


    # add a zone File to the icinga2-master configuration
    #
    # @param [Hash, #read] params
    # @option params [String] :host
    #
    # @example
    #    checkCert( { :host => 'icinga2-satellite' } )
    #
    # @return [Hash, #read] if config already created:
    #  * :status [Integer] 204
    #  * :message [String] Message
    # @return nil if successful
    def addToZoneFile( params = {} )

      host     = params.dig( :host )

      if( host == nil )

        return {
          :status   => 500,
          :message  => 'no host to add them in a icinga zone'
        }
      end

      logger.debug( host )

      if( !File.exists?( '/etc/icinga2/automatic-zones.d' ) )

        FileUtils.mkpath( '/etc/icinga2/automatic-zones.d' )
      end

      if( File.exists?( sprintf( '/etc/icinga2/automatic-zones.d/%s.conf', host ) ) )

        return {
          :status   => 204,
          :message  => 'cert are created'
        }
      end


      fileName = sprintf( '/etc/icinga2/automatic-zones.d/%s.conf', host )

      if( !File.exists?( fileName ) )

          File.open( fileName , 'a') { |f|
            f << "/*\n"
            f << " * generated at #{Time.now()} with IcingaCertService\n"
            f << " */\n"
            f << "object Endpoint \"#{host}\" {\n"
            f << "}\n\n"
            f << "object Zone \"#{host}\" {\n"
            f << "  endpoints = [ \"#{host}\" ]\n"
            f << "  parent = ZoneName\n"
            f << "}\n\n"
          }

      else

        file     = File.open( fileName, 'r' )
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
        result = contents.gsub( regexp_long, '' )

        logger.debug( result )

        scanEndpoint = result.scan(/object Endpoint(.*)"(?<endpoint>.+\S)"/).flatten
        scanZone     = result.scan(/object Zone(.*)"(?<zone>.+\S)"/).flatten

        if( scanEndpoint.include?( host ) && scanZone.include?( host ) )

          logger.debug( 'nothing to do' )
        else

          if( scanEndpoint.include?( host ) == false )

            logger.debug( 'missing endpoint' )

            File.open( fileName , 'a') { |f|
              f << "/*\n"
              f << " * generated at #{Time.now()} with IcingaCertService\n"
              f << " */\n"
              f << "object Endpoint \"#{host}\" {\n"
              f << "}\n\n"
            }
          end

          if( scanZone.include?( host ) == false )

            logger.debug( 'missing zone' )

            File.open( fileName , 'a') { |f|
              f << "object Zone \"#{host}\" {\n"
              f << "  endpoints = [ \"#{host}\" ]\n"
              f << "  parent = ZoneName\n"
              f << "}\n\n"
            }
          end

        end

      end

    end

    # reload the icinga2-master configuration
    #
    # call the system 'service' tool or 'supervisorctl' if this used
    def reloadIcingaConfig()

      # check init system
      # /usr/sbin/service
      # /usr/bin/supervisord

      command = nil

      if( File.exist?( '/usr/bin/supervisorctl' ) )

        command = '/usr/bin/supervisorctl reload icinga2'
      end

      if( File.exist?( '/usr/sbin/service' ) )

        command = '/usr/sbin/service icinga2 reload'
      end

      if( command != nil )

        result      = execCommand( { :cmd => command } )

        exitCode    = result.dig(:exit)
        exitMessage = result.dig(:message)

        if( exitCode != true )
          logger.error( sprintf( 'command \'%s\'', command ) )
          logger.error( sprintf( 'returned with exit-code %d', exitCode ) )
          logger.error( exitMessage )

          abort 'FAILED !!!'
        end

        return
      end

    end

  end

end

