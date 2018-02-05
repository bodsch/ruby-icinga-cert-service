
module IcingaCertService
  # Client Class to create on-the-fly a certificate to connect automaticly as satellite to an icinga2-master
  #
  #
  module Download

    # allows you to download a static file which is stored in the directory assets
    #
    # currently only 'icinga2_certificates.sh'
    #
    def download(params)

      file_name        = validate( params, required: true, var: 'file_name', type: String )
      request          = validate( params, required: true, var: 'request', type: Hash )

      whitelist = ['icinga2_certificates.sh']

      return { status: 500, message: 'file are unknown' } unless( whitelist.include?(file_name) )

      { status: 200, path: format('%s/assets', @base_directory), file_name: file_name }
    end
  end
end
