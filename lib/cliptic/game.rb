module Cliptic
  module Play
    class Interface
      def initialize(date:Date.today)
        @state   = State.new(date:date)
        @board   = Board.new(date:date)
        @top_bar = Top_Bar.new(date:date)
        @bot_bar = Bottom_Bar.new
        @looper  = Looper.new(game:self)
        @ctrller = Controller.new(game:self)
      end
      def play

      end
    end
    class Controller

    end
    class Looper

    end
    class Timer

    end
    class State

    end
  end
end
