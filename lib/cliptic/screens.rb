module Cliptic
  module Screens
    class Menu_Box
      include Windows
      attr_reader :box, :logo, :prompt, :line
      def initialize(y:, prompt:false)
        @line   = (Curses.lines-15)/2
        @box    = Window.new(y:y, x:33, line:line)
        @logo   = Logo.new(line:line+1)
        @prompt = prompt
      end
      def draw
        box.draw.refresh
        logo.draw.refresh
        draw_prompt if prompt
      end
      def draw_prompt
        box.setpos(4, (box.x-prompt.length)/2)
        box << prompt
        box.refresh
      end
    end
    class Menu
      include Windows
      attr_reader :win, :slct, :prompt, :top, :bottom
      def initialize(win_y:opts.length+6,
                     select_class:Selector, tick:nil,**)
        @prompt = false
        @top    = Top_Bar.new
        @bottom = Bottom_Bar.new
        @win    = Menu_Box.new(y:win_y, prompt:prompt)
        @slct   = select_class.new(opts:opts, ctrl:ctrl, tick:tick, line:win.line+5)
      end
      def select
        show
        slct.select
      end
      def ctrl
        {
          ?j => ->{slct.cursor += 1},
          ?k => ->{slct.cursor -= 1},
          ?q => ->{back},
          10 => ->{enter},
          3  => ->{exit}
        }
      end
      def enter(pre:->{hide}, post:->{show})
        slct.enter(pre:pre, post:post)
      end
      def back(cb:->{hide})
        slct.stop(cb:cb)
      end
      def hide
        win.box.erase
        win.box.noutrefresh
      end
      def show
        Curses.curs_set(0)
        top.draw
        bottom.draw
        win.draw
      end
    end
    class Stat_Menu < Menu
      attr_reader :stats
      def initialize(win_y:opts.length+6,
                     select_class:Selector, stat_line:Logo_Line+win_y-1, **)
        super(win_y:win_y, select_class:select_class, 
              tick:->{update_stats})
        @stats = Stats.new(line:win.line+win_y)
      end
      def update_stats
        stats.show(date:cur_date)
      end
      def hide
        stats.clear
        stats.noutrefresh
        super
      end
      def enter
        hide
        Play::Game.new(date:cur_date).run
        show
      end
    end
    class SQL_Stat_Menu < Stat_Menu
      include Database
      attr_reader :db, :dates
      def initialize(sql_class:)
        @db    = sql_class.new
        @dates = db.select.map{|d| Date.parse(d[0])}
        super
      end
      def opts
        dates.map{|d| d.to_long}
      end
      def cur_date
        dates[slct.cursor]
      end
    end
  end
end
