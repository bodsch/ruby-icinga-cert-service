
# frozen_string_literal: true

module IcingaCertService

  # namespace for version information
  module Version

    # major part of version
    MAJOR = 0
    # minor part of version
    MINOR = 8
    # tiny part of version
    TINY  = 3

  end

  # Current version of gem.
  VERSION = [Version::MAJOR, Version::MINOR, Version::TINY].compact * '.'

end
