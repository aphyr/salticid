module Ncurses
  # Returns size of screen [y, x]
  def self.dimensions
    x = Array.new
    y = Array.new
    Ncurses.getmaxyx(Ncurses.stdscr, y, x)
    [y.first, x.first]
  end

  class WINDOW
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
      y = Array.new
      x = Array.new
      getyx y, x
      [y.first, x.first]
    end
  end
end
