class Hydra
  class Interface
    require 'ncurses'
    require 'hydra/interface/ncurses'
    require 'hydra/interface/resizable'
    require 'hydra/interface/view'
    require 'hydra/interface/tab_view'
    require 'hydra/interface/host_view'

    COLORS = {
      :info => Ncurses::COLOR_WHITE,
      :error => Ncurses::COLOR_RED,
      :warn => Ncurses::COLOR_YELLOW,
      :debug => Ncurses::COLOR_CYAN,
      :finished => Ncurses::COLOR_GREEN
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

    attr_reader :hosts, :hydra

    def initialize(hydra)
      self.class.interfaces << self

      # Set up ncurses
      Ncurses.initscr
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.nonl
      Ncurses.stdscr.intrflush false
      Ncurses.stdscr.keypad true
      Ncurses.start_color
      Ncurses.use_default_colors

      @hydra = hydra
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
        :height => Ncurses.LINES - 1
      )
      hv.on_state_change do |state|
        @tabs.render
      end
      @tabs << hv
      tab.show
    end

    def colorize
      COLORS.each_with_index do |c, i|
        Ncurses.init_pair i + 1, c.last, -1
        COLOR_PAIRS[c.first] = Ncurses.COLOR_PAIR(i + 1)
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

    # List channels and topics
    def list(*channels)
      @connection.list *channels
    end

    # Mainloop
    def main
      @main = Thread.new do
        Thread.current.priority = -1
        trap("WINCH") { resize if Thread.current.alive? }

        loop do
          # Get character
          if IO.select [$stdin], nil, nil, 1
            char = @tabs.window.getch
          else
            Thread.pass
            retry
          end

          # Do stuff
          case char
          when ?\t
            @tabs.scroll
          when ?q
            shutdown
          when Ncurses::KEY_LEFT
            @tabs.scroll -1
          when Ncurses::KEY_RIGHT
            @tabs.scroll 1
          when Ncurses::KEY_PPAGE
            tab.scroll -tab.height / 2
          when Ncurses::KEY_NPAGE
            tab.scroll tab.height / 2
          when Ncurses::KEY_UP
            tab.scroll -1 
          when Ncurses::KEY_DOWN
            tab.scroll 1
          end
        end
      end
    end

    # Resize to fit display
    def resize
      # We need to nuke ncurses to pick up the new dimensions
      Ncurses.def_prog_mode
      Ncurses.endwin
      Ncurses.reset_prog_mode
      height, width = Ncurses.dimensions
   
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
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.endwin

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
