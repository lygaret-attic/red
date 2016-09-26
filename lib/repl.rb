require './lib/text_buffer'

# repl utilities
module Repl
  def self.countup
    TextBuffer.new.tap do |t|
      %w(ten nine eight seven six five four three two one).each do |w|
        t.insert(w + "!\n", at: 0)
      end
    end
  end
end
