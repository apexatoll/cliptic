module Cliptic
  module Interface
    class Top_Bar < Windows::Bar
      attr_reader :date
      def initialize(date:Date.today)
        super(line:0)
        @date = date
      end
      def draw
        super
        add_str(x:1, str:title, bold:true)
        add_str(x:title.length+2, str:date.to_long)
      end
      def title
        "cliptic:"
      end
      def reset_pos
        move(line:0, col:0)
      end
    end
    class Bottom_Bar < Windows::Bar
      def initialize
        super(line:Curses.lines-1)
      end
      def draw
        super
        noutrefresh
      end
      def reset_pos
        move(line:Curses.lines-1, col:0)
      end
    end
    class Logo < Windows::Grid
      attr_reader :text
      def initialize(line:, text:"CLIptic")
        super(y:1, x:text.length, line:line)
        @text = text
      end
      def draw(cp_grid:$colors[:logo_grid], 
               cp_text:$colors[:logo_text], bold:true)
        super(cp:cp_grid)
        bold(bold).color(cp_text)
        add_str(str:text)
        reset_attrs
        refresh
      end
    end
    class Menu_Box < Windows::Window
      include Interface
      attr_reader :logo, :title, :top_b, :bot_b, :draw_bars
      def initialize(y:, title:false)
        @logo = Logo.new(line:line+1)
        @title = title
        super(y:y, x:logo.x+4, line:line, col:nil)
        @top_b = Top_Bar.new
        @bot_b = Bottom_Bar.new
        @draw_bars = true
      end
      def draw
        super
        [top_b, bot_b].each(&:draw) if draw_bars
        logo.draw
        add_title if title
        self
      end
      def line
        (Curses.lines-15)/2
      end
      def add_title(y:4, str:title, cp:$colors[:title], bold:true)
        add_str(y:y, str:str, cp:cp, bold:bold)
      end
      def reset_pos
        move(line:line)
        logo.move(line:line+1)
        [top_b, bot_b].each(&:reset_pos)
      end
    end
    class Resizer < Menu_Box
      def initialize
        super(y:8, title:title)
      end
      def title
        "Screen too small"
      end
      def draw
        Screen.clear
        reset_pos
        super
        wrap_str(str:prompt, line:5)
        refresh
      end
      def show
        while Screen.too_small?
          draw; getch
        end
      end
      def prompt
        "Screen too small. Increase screen size to run cliptic."
      end
    end
    class Selector < Windows::Window
      attr_reader :opts, :ctrls, :run, :tick
      attr_accessor :cursor
      def initialize(opts:, ctrls:, x:, line:,
                     tick:nil, y:opts.length, col:nil)
        super(y:y, x:x, line:line, col:col)
        @opts, @ctrls, @tick = opts, ctrls, tick
        @cursor, @run = 0, true
      end
      def select
        while @run
          draw
          ctrls[getch]&.call
        end
      end
      def stop
        @run = false
      end
      def cursor=(n)
        @cursor = Pos.wrap(val:n,min:0,max:opts.length-1)
      end
      private
      def draw
        Curses.curs_set(0)
        setpos
        opts.each_with_index do |opt, i|
          standout if cursor == i
          self << format_opt(opt)
          standend
        end
        tick.call if tick
        refresh
      end
      def format_opt(opt)
        opt.to_s.center(x)
      end
    end
    class Date_Selector < Selector
      def initialize(opts:, ctrls:, line:, x:18, tick:)
        super(y:1, x:18, opts:opts, 
              ctrls:ctrls, line:line, tick:tick)
      end
      def format_opt(opt)
        opt.to_s.rjust(2, "0").center(6)
      end
    end
    class Stat_Window < Windows::Window
      def initialize(y:5, x:33, line:)
        super(y:y, x:x, line:line)
      end
      def show(date:, cp:$colors[:stats])
        draw(clr:true).color(cp)
        get_stats(date:date).each_with_index do |line, i|
          setpos(i+1, 8)
          self << line
        end
        color.noutrefresh
      end
      def get_stats(date:)
        Database::Stats.new(date:date).stats_str
      end
    end
    class Menu < Menu_Box
      attr_reader :selector, :height
      def initialize(height:opts.length+6,
                     sel:Selector, sel_opts:opts.keys,
                     tick:nil, **)
        super(y:height, title:title)
        @height = height
        @selector = sel.new(opts:sel_opts, ctrls:ctrls, line:line+5, x:logo.x, tick:tick)
      end
      def choose_opt
        show
        selector.select
      end
      def enter(pre_proc:->{hide}, post_proc:->{show})
        pre_proc.call if pre_proc
        opts.values[selector.cursor]&.call
        post_proc.call if post_proc
      end
      def back(post_proc:->{hide})
        selector.stop
        post_proc.call if post_proc
      end
      def show
        draw
      end
      def hide
        clear
      end
      def ctrls
        {
          ?j  => ->{selector.cursor += 1},
          ?k  => ->{selector.cursor -= 1},
          258 => ->{selector.cursor += 1},
          259 => ->{selector.cursor -= 1},
          10  => ->{enter},
          ?q  => ->{back},
          3   => ->{back},
          Curses::KEY_RESIZE => 
            ->{Screen.redraw(cb:->{redraw})}
        }
      end
      def reset_pos
        super
        selector.move(line:line+5)
      end
      def redraw
        reset_pos
        draw
      end
    end
    class Menu_With_Stats < Menu
      attr_reader :stat_win
      def initialize(height:opts.length+6, sel:Selector, **)
        super(height:height, sel:sel, sel_opts:opts, 
              tick:->{update_stats})
        @stat_win = Stat_Window.new(line:line+height)
      end
      def update_stats
        stat_win.show(date:stat_date)
      end
      def hide
        super
        stat_win.clear
      end
      def enter
        hide
        Main::Player::Game.new(date:stat_date).play
        show
      end
      def reset_pos
        super
        stat_win.move(line:line+height)
      end
    end
    class SQL_Menu_With_Stats < Menu_With_Stats
      include Database
      attr_reader :dates
      def initialize(table:)
        @dates = table.new
          .select_list.map{|d| Date.parse(d[0])}
        super
      end
      def opts
        dates.map{|d| d.to_long} || [nil]
      end
      def stat_date
        dates[selector.cursor]
      end
    end
    class Yes_No_Menu < Menu
      attr_reader :yes, :no, :post_proc
      def initialize(yes:, no:->{back}, post_proc:nil, title:nil)
        super
        @title = title
        @yes, @no, @post_proc = yes, no, post_proc
      end
      def opts
        {
          "Yes" => ->{yes.call; back; post},
          "No"  => ->{no.call; post}
        }
      end
      def post
        post_proc.call if post_proc
      end
    end
  end
end
