class Salticid
  class Interface
    class TabView < View

      def initialize(interface, params = {})
        super

        @tabs = []
        @active = -1
      end

      # Gets the active tab
      def active
        @tabs[@active] || nil
      end

      # Sets the active tab
      def active=(tab)
        @active = @tabs.index tab
        render
      end

      # Adds a tab (and switches to it by default)
      def add(tab)
        @tabs << tab
        @active = @tabs.size - 1
        render
      end

      alias :<< :add

      # Deletes a tab and switches to the previous tab
      def delete(tab)
        @tabs.delete tab
        previous
      end

      # Iterates over each tab
      def each(&block)
        @tabs.each &block
      end

      # Advances to the next tab
      def next
        scroll 1
      end

      # Goes to the previous tab
      def previous
        scroll -1
      end

      # Draws to screen
      def render
        return false if @tabs.empty?
        # Divide into regions

        # Ignore dividers
        width = @width - size + 1
        base_width = width / size
        regions = Array.new(size, base_width)
        
        # Add remainder to successive tabs.
        (width - base_width * size).times do |i|
          regions[i] += 1
        end

        # Move to start
        @window.move 0,0

        @tabs.each_with_index do |tab, i|
          if i > 0
            @window.addch Curses::ACS_VLINE
          end

          color = Interface::COLOR_PAIRS[tab.state]
          @window.attron color if color
          @window.attron Curses::A_BOLD
          @window.attron Curses::A_REVERSE if i == @active
          @window.addstr tab.to_s.slice(0,regions[i]).center(regions[i])
          @window.attroff Curses::A_REVERSE if i == @active
          @window.attroff Curses::A_BOLD
          @window.attroff color if color
        end

        @window.refresh
      end

      def resize(dimensions = nil)
        return unless super

        @tabs.each do |tab|
          tab.resize(
            :top => 1,
            :left => 0,
            :height => height - 1,
            :width => width
          )
        end
        active.render
      end

      # Moves by a number of tabs
      def scroll(delta = 1)
        active.hide rescue NoMethodError
        @active = (@active + delta).modulo(@tabs.size)
        active.show
        render
      end

      def shutdown
        @tabs.each do |tab|
          tab.shutdown
        end
        @tabs = []
      end

      # Number of tabs
      def size
        @tabs.size
      end

      # Switches the active tab to the specified label
      def switch_to_label(label)
        if index = @tabs.map{ |tab| tab.to_s }.index(label)
          @active = index
          render
        else
          raise RuntimeError.new("no tab labeled #{label}")
        end
      end
    end
  end
end
