
# -----------------------------------------------------------------------------
# Monkey patches

# Modify `Object`
#
#  original from (https://gist.github.com/Integralist/9503099)
#
# None of the above solutions work with a multi-level hash
# They only work on the first level: {:foo=>"bar", :level1=>{"level2"=>"baz"}}
# The following two variations solve the problem in the same way
# transform hash keys to symbols
#
# @example
#    multi_hash = { 'foo' => 'bar', 'level1' => { 'level2' => 'baz' } }
#    multi_hash = multi_hash.deep_string_keys
#
class Object

  # transform hash keys to symbols
  #
  # @example
  #    multi_hash = { 'foo' => 'bar', 'level1' => { 'level2' => 'baz' } }.deep_string_keys
  #
  # @return
  #    { foo: 'bar', level1: { 'level2' => 'baz' } }
  #
  def deep_symbolize_keys
    if( is_a?( Hash ) )
      return inject({}) do |memo, (k, v)|
        memo.tap { |m| m[k.to_sym] = v.deep_string_keys }
      end
    elsif( is_a?( Array ) )
      return map(&:deep_string_keys)
    end

    self
  end

  # transform hash keys to strings
  #
  #
  def deep_string_keys
    if( is_a?( Hash ) )
      return inject({}) do |memo, (k, v)|
        memo.tap { |m| m[k.to_s] = v.deep_string_keys }
      end
    elsif( is_a?( Array ) )
      return map(&:deep_string_keys)
    end

    self
  end

end

# -----------------------------------------------------------------------------

# check if is a checksum
#
class Object

  REGEX = /\A[0-9a-f]{32,128}\z/i
  CHARS = {
    md2: 32,
    md4: 32,
    md5: 32,
    sha1: 40,
    sha224: 56,
    sha256: 64,
    sha384: 96,
    sha512: 128
  }

  # return if this a checksum
  #
  # @example
  #    checksum.be_a_checksum
  #
  def be_a_checksum
    !!(self =~ REGEX)
  end

  # return true if the checksum created by spezified type
  #
  # @example
  #    checksum.produced_by(:md5)
  #
  #    checksum.produced_by(:sha256)
  #
  #
  def produced_by( name )
    function = name.to_s.downcase.to_sym

    raise ArgumentError, "unknown algorithm given to be_a_checksum.produced_by: #{function}" unless CHARS.include?(function)

    return true if( size == CHARS[function] )
    false
  end
end

# -----------------------------------------------------------------------------

# Monkey Patch to implement an Boolean Check
# original from: https://stackoverflow.com/questions/3028243/check-if-ruby-object-is-a-boolean/3028378#3028378
#
#
module Boolean; end
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

true.is_a?(Boolean) #=> true
false.is_a?(Boolean) #=> true

# -----------------------------------------------------------------------------

# add minutes
#
class Time

  # add minutes 'm' to Time Object
  #
  def add_minutes(m)
    self + (60 * m)
  end
end

# -----------------------------------------------------------------------------
