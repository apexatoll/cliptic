module Cliptic
  module Menus
    class Main < Screens::Menu
      def opts
        {
          "Play today" => ->{Play::Game.new.run},
          "Play yesterday" => ->{puts "yesterday"},
          "Select Date" => ->{Date_Menu.new.select},
          "This week" => ->{This_Week.new.select},
          "Recent Puzzles" => ->{Recents.new.select},
          "High Scores" => ->{High_Scores.new.select},
          "Quit" => ->{exit}
        }
      end
      def prompt
        "Main Menu"
      end
    end
    class Date_Menu < Screens::Stat_Menu
      attr_reader :opts
      def initialize
        set_date(date:Date.today)
        super(win_y:7, select_class:Date_Selector) 
      end
      def ctrl
        super.merge(
        {
          ?h => ->{slct.cursor -= 1},
          ?l => ->{slct.cursor += 1},
          ?j => ->{inc_date(1)},
          ?k => ->{inc_date(-1)},
          #10 => ->{play}
        }
        )
      end
      def set_date(date:)
        @opts = [] unless @opts
        @opts[0] = date.day
        @opts[1] = date.month
        @opts[2] = date.year
      end
      def cur_date
        Date.new(*@opts.reverse)
      end
      private
      def inc_date(n)
        case slct.cursor
        when 0 then inc_day(n)
        when 1 then inc_month(n)
        else @opts[2]+= n
        end
        set_date(date:Date.today)    if date_late
        set_date(date:Date.today<<9) if date_early
      end
      def date_late
        cur_date > Date.today
      end
      def date_early
        cur_date < Date.today << 9
      end
      def next_date(n)
        @opts.dup.tap{|d| d[slct.cursor] += n}
      end
      def inc_day(n)
        next_date(n).tap do |date|
          if valid?(date)
            @opts[0] += n
          elsif date[0] == 0
            set_date(date:cur_date-1)
          elsif date[0] > 28
            set_date(date:cur_date+1)
          end
        end
      end
      def inc_month(n)
        next_date(n).tap do |date|
          if valid?(date)
            @opts[1] += n
          elsif date[1] == 0
            set_date(date:cur_date<<1)
          elsif date[1] == 13
            set_date(date:cur_date>>1)
          elsif date[0] > 28
            set_date(date:last_date(date:date))
          end
        end
      end
      def last_day(date:)
        Date.new(date[2], date[1]+1, 1)-1
      end
      def valid?(date)
        Date.valid_date?(*date.reverse)
      end
      def prompt
        "Select Date to Play"
      end
    end
    class This_Week < Screens::Stat_Menu
      def days
        @days || [].tap do |a|
          7.times do |i|
            (Date.today-i).tap do |date|
              a << {date:date, done:Database::State.new(date:date).done}
            end
          end
        end
      end
      def cur_date
        days[slct.cursor][:date]
      end
      def opts
        @opts || days.map do |day|
          [day_str(day), ->{play(day[:date])}]
        end.to_h
      end
      def day_str(day)
        "#{day[:date].strftime("%A").ljust(9).center(12)} "\
          "[#{day[:done] ? Chars::Tick : " "}]"
      end
    end
    class High_Scores < Screens::SQL_Stat_Menu
      def initialize
        super(sql_class:Database::Scores)
      end
      def prompt
        "High Scores"
      end
    end
    class Recents < Screens::SQL_Stat_Menu
      def initialize
        super(sql_class:Database::Recents)
      end
      def prompt
        "Recently Played"
      end
    end
    class Puzzle_Complete < Screens::Menu
      def opts
        {
          "Exit" => ->{back(cb:->{Screen.clear})},
          "Quit" => ->{exit}
        }
      end
      def prompt
        "Puzzle Complete!"
      end
    end
    class Pause < Screens::Menu
      attr_reader :game
      def initialize(game:)
        super
        @game = game
      end
      def opts
        {
          "Continue" => ->{back; game.unpause},
          "Exit Game" => ->{back; game.hard_quit}
        }
      end
    end
    class Yes_No < Screens::Menu
      attr_reader :yes, :no, :prompt
      def initialize(yes:, no:->{back}, post:nil, prompt:nil)
        super
        @yes, @no, @prompt = prompt
      end
      def opts
        {
          "Yes" => ->{yes.call; back},
          "No"  => ->{no}
        }
      end
    end
  end
end
