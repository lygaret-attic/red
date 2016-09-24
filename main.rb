require 'dispel'
require './lib/text_buffer'

buffer   = TextBuffer.open('/var/log/syslog')
curr_top = 0

# draw app and redraw after each keystroke
Dispel::Screen.open do |screen|
  Dispel::Keyboard.output :timeout => 0.5 do |key|
    break if key == :"Ctrl+c"

    if key == :up
      curr_top -= 1
    elsif key == :down
      curr_top += 1
    elsif key == ' '
      curr_top += screen.lines - 1
    elsif key == :"Shift-up"
      curr_top -= 10
    elsif key == :"Shift-down"
      curr_top += 10
    end
    
    # start with the file content
    # we want to display the current window's text
    text = buffer.each_line.drop(curr_top).take(screen.lines - 1).force.join("\n")

    # draw the status line
    offset = screen.lines - text.count("\n") - 1
    status = offset.times.collect { "\n" }.join + Time.now.to_s
    text  += status

    # render the screen
    screen.draw text
  end
end
