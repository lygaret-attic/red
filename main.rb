require 'dispel'
require './lib/logger'
require './lib/assert'
require './lib/text_buffer'

Assert.enable

class Application

  def initialize
    @buffer    = TextBuffer.open('/var/log/kern.log.1')
    @scrollpos = 0
  end

  def draw(screen)
    # start with the file content
    # we want to display the current window's text
    lines = @buffer.lazy_lines(from: @scrollpos)
    lines = lines.take(screen.lines - 1).force

    # pad to the bottom
    if lines.length < screen.lines - 1
      lines.concat((screen.lines - 1 - lines.length).times.collect { "\n" })
    end

    # add the status line
    lcache = @buffer.instance_variable_get(:@lines)
    lines << "::::::: @#{@scrollpos} | #{lcache.length} -> #{lcache.last}"

    # render the screen
    screen.draw lines.join
  end

  def event(screen, key)
    if key == :up
      @scrollpos -= 1
    elsif key == :down
      @scrollpos += 1
    elsif key == ' '
      @scrollpos += (screen.lines - 1)
    elsif key == :enter
      @scrollpos += 500
    elsif key == :"Shift-up"
      @scrollpos -= 10
    elsif key == :"Shift-down"
      @scrollpos += 10
    end
  end

  def run
    # draw app and redraw after each keystroke
    Dispel::Screen.open do |screen|
      self.draw(screen)
      Dispel::Keyboard.output do |key|
        break if key == :"Ctrl+c"
        self.event(screen, key)
        self.draw(screen)
      end
    end
  end
    
end

Application.new.run
