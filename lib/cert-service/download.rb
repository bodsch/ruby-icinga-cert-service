
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module Download

    def download(params)

      file_name        = validate( params, required: true, var: 'file_name', type: String )
      request          = validate( params, required: true, var: 'request', type: Hash )

      return { status: 500, message: 'file are unknown' } unless( ['icinga2_certificates.sh'].include?(file_name) )

      { status: 200, path: format('%s/assets', @base_directory), file_name: file_name }

    end
  end
end
