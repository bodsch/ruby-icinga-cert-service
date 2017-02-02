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

module IcingaCertService

  class Client

    include Logging
    include Util::Tar
    include IcingaCertService::Executor
    include IcingaCertService::InMemoryDataCache

    def initialize( params = {} )

      @icingaMaster = params.dig( 'icingaMaster' )
      @tempDir      = '/tmp/icinga-pki'

      version              = '0.5.2-dev'
      date                 = '2017-02-02'

      logger.info( '-----------------------------------------------------------------' )
      logger.info( ' Icinga2 Cert Service' )
      logger.info( "  Version #{version} (#{date})" )
      logger.info( '  Copyright 2017 Bodo Schulz' )
      logger.info( '-----------------------------------------------------------------' )
      logger.info( '' )

    end


    def readAPICredetials()

      file = '/var/tmp/api-users.conf'

regex = /cert-api/
found = false
data = Array.new()

      f = File.open( file ,"r")
      f.each{ |line|

        if( found )
          data << line
        end
        if( line =~ regex )
          found = true
        end
      }
      puts data # .join("\n")

      puts data.select { |name| name =~ /password/ }


#       fh.each_with_index{|line, i| puts "#{i+1}: #{line}"}



#         if( line.=~ /^object ApiUser "cert-api"*$/ )
#         end
#         logger.debug( line )
#         print line without the new line if line does not contain  /--+/
#         if line contains /--+/
#           print line with a new line
#         end
#      end

    end


    def createCert( params = {} )

      host = params.dig(:host)

      if( host == nil )
        logger.error( 'no hostname' )

        return {
          :status  => 500,
          :message => 'no hostname'
        }
      end

      if( @icingaMaster == nil )

        serverName  = Socket.gethostbyname( Socket.gethostname ).first
        serverIp    = IPSocket.getaddress( Socket.gethostname )
      else
        serverName  = @icingaMaster
        serverIp    = IPSocket.getaddress( serverName )
      end

      pkiMasterKEY = sprintf( '/etc/icinga2/pki/%s.key', serverName )
      pkiMasterCSR = sprintf( '/etc/icinga2/pki/%s.csr', serverName )
      pkiMasterCRT = sprintf( '/etc/icinga2/pki/%s.crt', serverName )
      pkiMasterCA  = '/etc/icinga2/pki/ca.crt'

      if( !File.exist?( '/etc/icinga2/pki' ) )

        return {
          :status  => 500,
          :message => 'no PKI directory'
        }
      end

      FileUtils.mkpath( '/etc/icinga2/zone.d/global-templates' )
      FileUtils.mkpath( sprintf( '/etc/icinga2/zone.d/%s', host ) )

      #
      if( ! File.exists?( '/etc/icinga2/zone.d/global-templates/services.conf' ) )

        FileUtils.mv( '/etc/icinga2/conf.d/services.conf', '/etc/icinga2/zone.d/global-templates/services.conf' )
      end

      logger.debug( sprintf( 'search PKI files for \'%s\'', serverName ) )

      if( !File.exist?( pkiMasterKEY ) || !File.exist?( pkiMasterCSR ) || !File.exist?( pkiMasterCRT ) )

        logger.error( 'missing file' )

        logger.debug( pkiMasterKEY )
        logger.debug( pkiMasterCSR )
        logger.debug( pkiMasterCRT )

        return {
          :status  => 500,
          :message => 'missing file'
        }
      end

      tempHostDir = sprintf( '%s/%s', @tempDir, host )
      uid         = File.stat( '/etc/icinga2/conf.d' ).uid

      if( ! File.exist?( tempHostDir ) )
        FileUtils.mkpath( tempHostDir )
      end

      if( File.exists?( tempHostDir ) )
        FileUtils.chown_R( uid, 'nobody', @tempDir )
        FileUtils.chmod_R( 0777, @tempDir )
      end

      if( ! File.exist?( tempHostDir ) )

        logger.error( 'cant create temporary directory' )

        exit 1
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
          logger.error( sprintf( 'returned with exit-code %d', exitCode ) )
          logger.error( exitMessage )

          abort 'FAILED !!!'
        end

        if( exitMessage =~ /information\// )

          #logger.debug( 'no ticket' )
        else

          pkiTicket = exitMessage.strip

          nextCommand = nextCommand.gsub!( '%PKI_TICKET%', pkiTicket)

        end
      }

      FileUtils.cp( pkiMasterCA, sprintf( '%s/ca.crt', tempHostDir ) )

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

      checksum = Digest::SHA2.hexdigest( File.read( archiveName ) )
      timestamp = Time.now()
      timeout   = timestamp.addMinutes( 10 )

      logger.debug( sprintf( ' timestamp : %s', timestamp.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )
      logger.debug( sprintf( ' timeout   : %s', timeout.to_datetime.strftime("%d-%m-%Y %H:%M:%S") ) )

      # store datas in-memory
      save( checksum, { :timestamp => timestamp, :timeout => timeout, :host => host } )

      # remove the temporars data
      FileUtils.rm_rf( tempHostDir )

      return {
        :masterName  => serverName,
        :masterIp    => serverIp,
        :checksum    => checksum,
        :timestamp   => timestamp.to_i,
        :timeout     => timeout.to_i
      }

    end


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

        File.write( fileName, text.gsub( /const TicketSalt = ""/, "const TicketSalt = \"#{ticketSalt}\"" )
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
        :masterName  => serverName,
        :masterIp    => serverIp,
        :ticket      => hostTicket,
        :timestamp   => timestamp.to_i
      }

    end


    def checkCert( params = {} )

      host     = params.dig( :host )
      checksum = params.dig( :request, 'HTTP_X_CHECKSUM' )

      if( host == nil || checksum == nil )

#         logger.debug( host )
#         logger.debug( checksum )

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


    def addToZoneFile( params = {} )

      host     = params.dig( :host )

      if( host == nil )

        return {
          :status   => 500,
          :message  => 'no host to add them in a icinga zone'
        }
      end

      logger.debug( host )

      fileName = '/etc/icinga2/zones.conf'

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
            f << "/*\n"
            f << " * generated at #{Time.now()} with IcingaCertService\n"
            f << " */\n"
            f << "object Zone \"#{host}\" {\n"
            f << "  endpoints = [ \"#{host}\" ]\n"
            f << "  parent = ZoneName\n"
            f << "}\n\n"
          }
        end

      end


    end


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

