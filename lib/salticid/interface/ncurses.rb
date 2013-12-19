module Curses
  # Returns size of screen [y, x]
  def self.dimensions
    [Curses.stdscr.maxy, Curses.stdscr.maxx]
  end

  class Window
    # Adds a FormattedString
    def add_formatted_string(string)
      string.each do |part|
        # Set attributes
        part[1..-1].each {| attribute| attron attribute }
        addstr part[0]
        # Unset attributes
        part[1..-1].each {| attribute| attroff attribute }
      end
    end

    # Returns cursor y and x coordinates.
    def cursor
      [cury, curx]
    end
  end
end
