module Cliptic
  module Menus
    class Main < Interface::Menu
      def opts
        {
          "Play Today" => ->{Cliptic::Main::Player::Game.new.play},
          "Select Date"=> ->{Select_Date.new.choose_opt},
          "This Week"  => ->{This_Week.new.choose_opt},
          "Recent Puzzles" => ->{Recent_Puzzles.new.choose_opt},
          "High Scores"=> ->{High_Scores.new.choose_opt},
          "Quit"       => ->{exit}
        }
      end
      def title
        "Main Menu"
      end
    end
    class Select_Date < Interface::Menu_With_Stats
      attr_reader :opts, :earliest_date
      def initialize
        @earliest_date = (Date.today << 9) + 1
        set_date(date:Date.today)
        super(height:7, sel:Interface::Date_Selector)
      end
      def title
        "Select Date"
      end
      def ctrls
        super.merge({
          ?h  => ->{selector.cursor -= 1},
          ?l  => ->{selector.cursor += 1},
          ?j  => ->{inc_date(1)},
          ?k  => ->{inc_date(-1)},
          258 => ->{inc_date(1)},
          259 => ->{inc_date(-1)},
          260 => ->{selector.cursor -= 1},
          261 => ->{selector.cursor += 1}
        })
      end
      def stat_date
        Date.new(*@opts.reverse)
      end
      private
      def set_date(date:)
        @opts = [] unless @opts
        @opts[0] = date.day
        @opts[1] = date.month
        @opts[2] = date.year
      end
      def next_date(n)
        @opts.dup.tap{|d| d[selector.cursor] += n }
      end
      def inc_date(n)
        case selector.cursor
        when 0 then inc_day(n)
        when 1 then inc_month(n)
        when 2 then @opts[2] += n
        end
        check_in_range
      end
      def inc_day(n)
        next_date(n).tap do |date|
          if valid?(date)
            @opts[0]+= n
          elsif date[0] == 0
            set_date(date:stat_date-1)
          elsif date[0] > 28
            set_date(date:stat_date+1)
          end
        end
      end
      def inc_month(n)
        next_date(n).tap do |date|
          if valid?(date)
            @opts[1] += n
          elsif date[1] == 0
            set_date(date:stat_date << 1)
          elsif date[1] == 13
            set_date(date:stat_date >> 1)
          elsif date[0] > 28
            set_date(date:last_day_of_month(date:date))
          end
        end
      end
      def valid?(date)
        Date.valid_date?(*date.reverse)
      end
      def last_day_of_month(date:)
        Date.new(date[2], date[1]+1, 1)-1
      end
      def check_in_range
        set_date(date:Date.today)    if date_late?
        set_date(date:earliest_date) if date_early?
      end
      def date_late?
        stat_date > Date.today
      end
      def date_early?
        stat_date < earliest_date
      end
    end
    class This_Week < Interface::Menu_With_Stats
      def days
        @days || 7.times.map{|i| Date.today - i}
      end
      def stat_date
        days[selector.cursor]
      end
      def opts
        @opts || days.map{|d| d.strftime("%A").ljust(9).center(12) + tickbox(d)}
      end
      def title
        "This Week"
      end
      def tickbox(date)
        "[#{Database::State.new(date:date).done ? Chars::Tick : " "}]"
      end
    end
    class Recent_Puzzles < Interface::SQL_Menu_With_Stats
      def initialize
        super(table:Database::Recents)
      end
      def title
        "Recently Played"
      end
    end
    class High_Scores < Interface::SQL_Menu_With_Stats
      def initialize
        super(table:Database::Scores)
      end
      def title
        "High Scores"
      end
    end
  end
end
