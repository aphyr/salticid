class Salticid
  class Interface
    require 'curses'
    require 'salticid/interface/ncurses'
    require 'salticid/interface/resizable'
    require 'salticid/interface/view'
    require 'salticid/interface/tab_view'
    require 'salticid/interface/host_view'

    COLORS = {
      :info => Curses::COLOR_WHITE,
      :error => Curses::COLOR_RED,
      :warn => Curses::COLOR_YELLOW,
      :debug => Curses::COLOR_CYAN,
      :finished => Curses::COLOR_GREEN
    }
    COLOR_PAIRS = {}

    # Keys
    KEY_SPACE = 32
    KEY_ENTER = 13
    KEY_SCROLL_UP = 258
    KEY_SCROLL_DOWN = 259

    def self.interfaces
      @interfaces ||= []
    end

    def self.shutdown *args
      @interfaces.each do |i|
        i.shutdown *args
      end
    end

    attr_reader :hosts, :salticid

    def initialize(salticid)
      self.class.interfaces << self


      # Set up ncurses
      Curses.init_screen
      Curses.cbreak
      Curses.noecho
      Curses.nonl
      # Gone in Ruby Curses because ???
      # Curses.stdscr.intrflush false
      Curses.stdscr.keypad true
      Curses.start_color
      Curses.use_default_colors

      @salticid = salticid
      @hosts = []
      @tabs = TabView.new(
        self,
        :height => 1
      )

      @tabs.window.keypad true

      colorize
    end

    # Add a new tab interface backed by source.
    def add_tab(host)
      @tabs.active.hide if tab

      hv = HostView.new(
        self,
        :host => host,
        :top => 1,
        :height => Curses.lines - 1
      )
      hv.on_state_change do |state|
        @tabs.render
      end
      @tabs << hv
      tab.show
    end

    # Set up colors
    def colorize
      COLORS.each_with_index do |c, i|
        pair_num = i + 1
        Curses.init_pair pair_num, c.last, -1
        COLOR_PAIRS[c.first] = pair_num
      end
    end

    def delete_tab(target)
      begin
        target.hide
        @tabs.delete target
      ensure
        tab.show if tab
      end
    end

    # Join the mainloop.
    def join
      @main.join
    end

    # Mainloop
    def main
      @main = Thread.new do
        Thread.current.priority = -1
        main_thread = Thread.current
        trap("WINCH") { resize if main_thread.alive? }

        loop do
          # Get character
          if IO.select [$stdin], nil, nil, 1
            char = @tabs.window.getch
          else
            Thread.pass
            next
          end

          # Do stuff
          case char
          when 9 # tab
            @tabs.scroll
          when 113 # q
            shutdown
          when Curses::KEY_LEFT
            @tabs.scroll -1
          when Curses::KEY_RIGHT
            @tabs.scroll 1
          when Curses::KEY_PPAGE
            tab.scroll -tab.height / 2
          when Curses::KEY_NPAGE
            tab.scroll tab.height / 2
          when Curses::KEY_UP
            tab.scroll -1 
          when Curses::KEY_DOWN
            tab.scroll 1
          end
        end
      end
    end

    # Resize to fit display
    def resize
      # We need to nuke ncurses to pick up the new dimensions
      Curses.def_prog_mode
      Curses.close_screen
      Curses.reset_prog_mode
      height, width = Curses.dimensions
   
      # Resize tabs 
      @tabs.resize(
       :width => width,
       :height => height
      )
      @tabs.render
    end

    # Shut down interface
    def shutdown(and_exit = true)
      # Shut down views
      @tabs.shutdown
     
      # Shut down ncurses
      Curses.echo
      Curses.nocbreak
      Curses.nl
      Curses.close_screen

      # Stop interface
      @main.exit rescue nil

      # Exit if okay
      exit if and_exit
    end

    # Switch to a different conversation
    def switch(target = nil)
      if target
        # Switch to a specific tab
        @tabs.switch_to_label target
      else
        # Switch to the next tab
        @tabs.scroll
      end
    end

    def tab
      @tabs.active
    end
  end
end
