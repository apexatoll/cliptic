module Cliptic
  module Terminal
    class Command
      def self.run
        ARGV.size > 0 ?
          parse_args : main_menu
        rescue StandardError => e
          Curses.close_screen
          abort(e.message)
      end
      private
      def self.setup
        Screen.setup
        Config::Setter.new.set
        at_exit{close}
      end
      def self.main_menu
        setup
        Cliptic::Menus::Main.new.choose_opt
      end
      def self.parse_args
        case arg = ARGV.shift
        when "reset", "-r" then Reset_Stats.route.call
        when "today", "-t" then play(ARGV.shift.to_i)
        end
      end
      def self.play(offset)
        setup
        Cliptic::Main::Player::
          Game.new(date:Date.today+offset).play
      end
      def self.close
        Curses.close_screen
        puts "Thanks for playing!"
      end
    end
    class Reset_Stats
      def self.route
        if valid_options.include?(c = ARGV.shift)
          ->{confirm_reset(c)}
        else 
          ->{puts "Unknown option #{c}"}
        end
      end
      private
      def self.valid_options
        ["scores", "all", "states", "recents"]
      end
      def self.confirm_reset(table)
        puts prompt(table)
        user_confirmed? ?
          reset(table) : 
          puts("Wise choice")
      end
      def self.prompt(table)
        <<~prompt
        cliptic: Reset #{table}
        Are you sure? This cannot be undone! [Y/n]
        prompt
      end
      def self.user_confirmed?
        gets.chomp === "Y"
      end
      def self.reset(table)
        table == "all" ?
          Database::Delete.all :
          Database::Delete.table(table)
      end
    end
  end
end

