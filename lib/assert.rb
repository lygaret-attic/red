require 'forwardable'
require 'singleton'

module Assert
  class << self
    extend Forwardable

    def enable
      @instance = Assert::RealAssert.instance
    end

    def disable
      @instance = Assert::NullAssert.instance
    end

    def_delegator :@instance, :assert
  end

  class AssertionError < StandardError; end

  class NullAssert
    include Singleton
    def assert(message); end
  end

  class RealAssert
    include Singleton

    def assert(message)
      raise AssertionError, message unless yield
    rescue => ex
      raise AssertionError, "#{message}, cause: #{ex}"
    end
  end
end

# start out disabled
Assert.disable

# mix assert into Kernel
module Kernel
  def assert(*args)
    Assert.assert(*args)
  end
end
