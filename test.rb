require 'date'

class Game
  def initialize(date:Date.today)
    @state = State.new(date:date)
    @board = Board.new(date:date)
    @top_b = Top_Bar.new
    @bot_b = Bot_Bar.new
    @timer = Timer.new(time:state.time,
                       bar:top_b,cb:->{board.update})
  end
  def play
    setup
    if state.done
      Puzzle_Complete.new.select
    else
      Recents.new.add(date:date)
      @timer = Timer.new(time:state.time,bar:top_b,tick:->{board.update})
      [
        Thread.new{timer.start}
      ].map(&:join)
    end
  end
  private
  def setup

  end
end

class Play
  def initialize(game:)
    @game = game
    @ctrl = Controller.new(game:game)
    @cont = true
  end
  def run

  end
  def finished?
    game.board.puzzle.complete? || !cont
  end

end
