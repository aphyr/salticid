class Hydra
  class Interface
    module Resizeable
      def resize(dimensions = nil)
        case dimensions
        when Hash
          # Resize self
          @height = dimensions[:height] if dimensions[:height]
          @width  = dimensions[:width]  if dimensions[:width]
          @top    = dimensions[:top]    if dimensions[:top]
          @left   = dimensions[:left]   if dimensions[:left]

          if @window
            # Resize window
            @window.mvwin @top, @left
            @window.resize @height, @width
          end

          true
        else
          # Resize parent
          @interface.resize
          false
        end
      end
    end
  end
end
