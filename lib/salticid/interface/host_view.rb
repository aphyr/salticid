class Salticid
  class Interface
    class HostView < View

      attr_accessor :messages, :window, :state

      def initialize(interface, params = {})
        @messages = []

        @scroll_position = -1

        super

        @host = params[:host]
        @host.on_log do |message|
          self << message
        end

        @state = nil
        @on_state_change = proc { |state| }
      end

      def <<(message)
        # Scroll if at bottom
        @scroll_position += 1 if @scroll_position == @messages.size - 1

        @messages << message

        if @state != message.severity
          @state = message.severity
          @on_state_change.call(@state)
        end
        
        render
      end

      def on_state_change(&block)
        @on_state_change = block
      end

      def render
        return if @hidden

        @window.clear

        lines_left = @height
        message_i = @scroll_position
        while message_i >= 0
          # Message
          message = @messages[message_i]
          message_i -= 1

          # Time
          time = message.time.strftime "%H:%M:%S"

          text = message.text
          color = Interface::COLOR_PAIRS[message.severity]
          
          offset = time.length + 1

          width = @width - offset
          lines = text.scan(/[^\n]{1,#{width}}/m)

          # Put lines in reverse
          i = lines.size
          while i > 0
            i -= 1
            line = lines[i]

            lines_left -= 1
            break if lines_left < 0

            if i.zero?
              # Put top line
              @window.setpos lines_left, 0
              @window.addstr time + ' '
              @window.attron Curses::A_BOLD
              @window.color_set color if color
              @window.addstr line
            else
              # Put hanging line
              @window.attron Curses::A_BOLD
              @window.attron color if color
              @window.setpos lines_left, offset
              @window.addstr line
            end
            @window.color_set Interface::COLOR_PAIRS[:info] if color
            @window.attroff Curses::A_BOLD

            unless @window.cursor[1] == 0
              # Clear rest of line
              @window.clrtoeol
            end
          end
        end
        @window.refresh
      end

      def to_s
        @host.name
      end

      # Scrolls the window by delta messages
      def scroll(delta)
        @scroll_position += delta
        if @scroll_position < 0
          @scroll_position = 0
        elsif @scroll_position >= @messages.size
          @scroll_position = @messages.size - 1
        end

        render
      end

      def shutdown
        @host.on_log do |message|
          puts message.text
        end
        @host = nil
      end
    end
  end
end
