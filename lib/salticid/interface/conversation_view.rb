module IRC
  require ROOT + '/interface'
  require ROOT + '/view'
  class Interface
    class ConversationView < View

      attr_accessor :messages, :window

      COLORS = [
        Ncurses::COLOR_WHITE,
        Ncurses::COLOR_RED,
        Ncurses::COLOR_GREEN,
        Ncurses::COLOR_YELLOW,
        Ncurses::COLOR_BLUE,
        Ncurses::COLOR_MAGENTA,
        Ncurses::COLOR_CYAN
      ] 

      def initialize(interface, params = {})
        @messages = []

        @scroll_position = -1

        super

        @color_index = 0

        @color_map = Hash.new do |hash, key|
          if key
            hash[key] = @color_index.modulo Ncurses.COLOR_PAIRS
            @color_index += 1
          else
            nil
          end
        end

        colorize
      end

      def <<(message)
        # Scroll if at bottom
        @scroll_position += 1 if @scroll_position == @messages.size - 1

        # Add color
        if message.respond_to? :user
          @color_map[message.user.nick]
        end

        @messages << message
        render
      end

      # Set up colors
      def colorize
        COLORS.each_with_index do |color, i|
          Ncurses.init_pair i, color, Ncurses::COLOR_BLACK
        end
      end

      def render
        if @hidden
          return
        end

        @window.erase

        lines_left = @height
        message_i = @scroll_position
        while message_i >= 0
          # Message
          message = @messages[message_i]
          message_i -= 1

          IRC.log "displaying message #{message}"

          # Time
          time = message.time.strftime "%H:%M:%S"

          case message
          when PrivMsg
            color = Ncurses.COLOR_PAIR(@color_map[message.user.nick])
            user = message.user.to_s || ''
            text = message.text
          when Event
            user = ''
            text = message.text
          when Command
            user = message.user.to_s || ''
            text = message.text
          else
            user = message.user.to_s || ''
            text = message.command + ' ' + message.params.join(" ")
          end
          
          offset = time.length + user.length + 3

          lines = [text[0, @width - offset]]
          if remaining = text[@width - offset..-1]
            lines += remaining.lines(@width - offset - 1)
          end

          # Put lines in reverse
          i = lines.size
          while i > 0
            i -= 1
            line = lines[i]

            lines_left -= 1
            break if lines_left < 0

            if i.zero?
              # Put top line
              @window.move lines_left, 0
              @window.addstr time + ' '
              @window.attron Ncurses::A_BOLD
              @window.attron color if color
              @window.addstr user
              @window.attroff color if color
              @window.attroff Ncurses::A_BOLD
              @window.addstr ': '
              @window.addstr line
            else
              # Put hanging line
              @window.move lines_left, offset
              @window.addstr line
            end

            unless @window.cursor[1] == 0
              # Clear rest of line
              @window.clrtoeol
            end
          end
        end
        @window.refresh
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
    end
  end
end
