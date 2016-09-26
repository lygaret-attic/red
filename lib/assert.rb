require 'forwardable'
require 'singleton'

module Assert
  class AssertionError < StandardError; end

  def self.patch_kernel
    Kernel.module_eval do
      def assert(*args, &block)
        Assert.assert(*args, &block)
      end
    end
  end

  def self.enable
    @instance = Assert::RealAssert.instance
  end

  def self.disable
    @instance = Assert::NullAssert.instance
  end

  def self.assert(message, &block)
    @instance.assert(message, &block)
  end

  class NullAssert
    include Singleton
    def assert(message); end
  end

  class RealAssert
    include Singleton

    def assert(message)
      raise AssertionError, message unless yield
    end
  end
end

# start out disabled
Assert.disable

# add #assert to kernel
Assert.patch_kernel
