class Salticid
  class Interface
    class View
      include Resizeable

      attr_accessor :window, :height, :width, :top, :left

      def initialize(interface, params = {})
        @interface = interface
        @height = params[:height] || Curses.lines
        @width = params[:width] || Curses.cols
        @top = params[:top] || 0
        @left = params[:left] || 0

        @window = Curses::Window.new @height, @width, @top, @left
      end

      def height=(height)
        @height = height
        @window.resize @height, @width
      end

      def hide
        @hidden = true
        @window.clear
      end

      def left=(left)
        @left = left
        @window.mvwin @top, @left
      end

      def show
        @hidden = false
        render
      end

      def top=(top)
        @top = top
        @window.mvwin @top, @left
      end

      def width=(width)
        @width = width
        @window.resize @height, @width
      end
    end
  end
end
