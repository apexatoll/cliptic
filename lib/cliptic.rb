require 'cgi'
require 'curb'
require 'curses'
require 'date'
require 'fileutils'
require 'json'
require 'sqlite3'
require 'time'

require_relative "cliptic/version"

module Cliptic
  class Pos
    def self.mk(y,x)
      { y:y.to_i, x:x.to_i }
    end
    def self.wrap(val:, min:, max:)
      val > max ? min : (val < min ? max : val)
    end
    def self.change_dir(dir)
      dir == :a ? :d : :a
    end
  end
  class Date < Date
    def to_long
      self.strftime('%A %b %-d %Y')
    end
  end
  class Time < Time
    def self.abs(t)
      Time.at(t).utc
    end
    def to_s
      self.strftime("%T")
    end
  end
  module Chars
    HL   = "\u2501"
    LL   = "\u2517"
    LU   = "\u250F"
    RL   = "\u251B"
    RU   = "\u2513"
    TD   = "\u2533"
    TL   = "\u252B"
    TR   = "\u2523"
    TU   = "\u253B"
    VL   = "\u2503"
    XX   = "\u254B"
    Tick = "\u2713"
    Nums = ["\u2080", "\u2081", "\u2082", "\u2083",
            "\u2084", "\u2085", "\u2086", "\u2087", 
            "\u2088", "\u2089"]
    MS = "\u2588"
    LS = "\u258C"
    RS = "\u2590"
    Block = RS+MS+LS
    def self.small_num(n)
      n.to_s.chars.map{|n| Nums[n.to_i]}.join
    end
  end
  class Screen
    def self.setup
      Curses.init_screen
      Curses.start_color
      Curses.raw
      Curses.use_default_colors
      Curses.noecho
      Curses.curs_set(0)
      set_colors
    end
    def self.set_colors
      1.upto(8) do |i|
        Curses.init_pair(i, i, -1)
        Curses.init_pair(i+8, 0, i)
      end
    end
    def self.clear
      Curses.stdscr.clear
      Curses.stdscr.refresh
    end
    def self.too_small?
      Curses.lines < 36 || Curses.cols < 61
    end
    def self.redraw(cb:)
      if Screen.too_small?
        Interface::Resizer.new(redraw:cb).show
      else
        cb.call
      end
    end
  end
  module Config
    Dir_Path  = "#{Dir.home}/.config/cliptic"
    File_Path = "#{Dir_Path}/cliptic.rc"
    class Default
      def self.colors
        {
          box:8, grid:8, bar:16, logo_grid:8, 
          logo_text:1, title:3, stats:2, active_num:3, 
          num:8, block:8, I:15, N:12, correct:2, 
          incorrect:1, meta:3, cluebox:8
        }
      end
      def self.config
        {
          auto_advance:1,
          auto_mark:1,
          auto_save:1
        }
      end
    end
    class Setter
      attr_reader :colors, :config
      def initialize
        @colors = Default.colors
        @config = Default.config
      end
      def set
        read
        $colors = @colors
        $config = @config
      end
      def read
        Reader.new.tap do |file|
          keys.each do |dest, key|
            dest.merge!(file.read(**key))
          end
        end
      end
      def keys
        {
          @colors => {key:"hi"},
          @config => {key:"set"}
        }
      end
    end
    class Reader
      attr_reader :lines
      def initialize
        @lines = File.read(File_Path).each_line.map.to_a
      end
      def read(key:)
        lines.grep(/^\s#{key}/)
          .map{|l| l.gsub(/^\s*#{key}\s+/, "")
          .split(/\s+/)}
          .map{|k, v| [k.to_sym, v.to_i]}
          .to_h
      end
    end
    class Maker

    end
  end
  module Database
    Path = "#{Dir.home}/db/cw.db"
    class SQL
      attr_reader :db, :table
      def initialize(table:)
        @db, @table = SQLite3::Database.open(Path), table
        db.results_as_hash = true
        self
      end
      def make_table
        db.execute(sql_make)
      end
      def select(cols:"*", where:nil, order:false, limit:false)
        db.execute(
          sql_select(cols:cols, where:where, 
                     order:order, limit:limit),
          where&.values&.map(&:to_s)
        )
      end
      def insert(values:)
        db.execute(sql_insert(values:values), 
                   values.values)
      end
      def update(values:, where:)
        db.execute(sql_update(values:values, where:where), [values.values], [where.values])
      end
      def delete(where:nil)
        db.execute(sql_delete(where:where), where&.values)
      end
      private
      def sql_make
        "CREATE TABLE IF NOT EXISTS #{table}(#{
          cols.map{|col,type|"#{col} #{type}"}.join(", ")
        })"
      end
      def sql_select(cols:, where:, order:, limit:)
        "SELECT #{cols} FROM #{table}" +
          (where ? where_str(where)  : "") +
          (order ? order_str(order)  : "") +
          (limit ? " LIMIT #{limit}" : "")
      end
      def sql_insert(values:)
        <<~sql
        INSERT INTO #{table}(#{values.keys.join(", ")})
        VALUES (#{Array.new(values.length, "?").join(", ")})
        sql
      end
      def sql_update(values:, where:)
        <<~sql
        UPDATE #{table}
        SET #{placeholder(values.keys, ", ")}
        WHERE #{placeholder(where.keys)}
        sql
      end
      def sql_delete(where:)
        <<~sql
        DELETE FROM #{table} #{where ? where_str(where) : ""}
        sql
      end
      def where_str(where)
        " WHERE #{placeholder(where.keys)}"
      end
      def order_str(order)
        " ORDER BY #{order.keys
          .map{|k| "#{k} #{order[k]}"}
          .join(", ")}" 
      end
      def placeholder(keys, glue=" AND ")
        keys.map{|k| "#{k} = ?"}.join(glue)
      end
    end
    class State < SQL
      include Chars
      attr_reader :date, :time, :chars, :n_done, :n_tot,
        :reveals, :done
      attr_accessor :reveals
      def initialize(date:Date.today)
        super(table:"states").make_table
        @date = date
        set
      end
      def cols
        {
          date: :DATE, time: :INT, chars: :TEXT, 
          n_done: :INT, n_tot: :INT, reveals: :INT, 
          done: :INT
        }
      end
      def exists?
        @exists || query.count > 0
      end
      def save(game:)
        exists? ? save_existing(game) : save_new(game)
      end
      def delete
        super(where:{date:date.to_s})
        @exists = false
        set
      end
      private
      def set
        @time,@chars,@n_done,@n_tot,@reveals,@done =
          exists? ? instantiate : blank
      end
      def instantiate
        [
          query[0]["time"].to_i,
          parse_chars(query[0]["chars"]),
          query[0]["n_done"].to_i,
          query[0]["n_tot"].to_i,
          query[0]["reveals"].to_i,
          query[0]["done"].to_i == 1
        ]
      end
      def blank
        [ 0, false, nil, nil, 0, false ]
      end
      def query
        @query || select(where:{date:date})
      end
      def parse_chars(str)
        JSON.parse(str, symbolize_names:true)
      end
      def build(game:)
        {
          date:    date.to_s,
          time:    game.timer.time.to_i,
          chars:   gen_chars(game),
          n_done:  game.board.puzzle.n_clues_done,
          n_tot:   game.board.puzzle.n_clues,
          reveals: reveals,
          done:    game.board.puzzle.complete? ? 1 : 0
        }
      end
      def gen_chars(game)
        JSON.generate(game.board.save_state)
      end
      def save_existing(game)
        update(where:{date:date.to_s}, values:build(game:game))
      end
      def save_new(game)
        insert(values:build(game:game))
        @exists = true
      end
    end
    class Stats < State
      def initialize(date:Date.today)
        super(date:date)
      end
      def stats_str
        (exists? ? exist_str : new_str).split("\n")
      end
      def exist_str
        <<~stats
          Time  #{VL} #{Time.abs(time).to_s}
          Clues #{VL} #{n_done}/#{n_tot}
          Done  #{VL} [#{done ? Tick : " "}]
        stats
      end
      def new_str
        "\n  Not attempted\n"
      end
    end
    class Recents < SQL
      attr_reader :date
      def initialize
        super(table:"recents").make_table
      end
      def cols
        {
          date: :DATE,
          play_date: :DATE,
          play_time: :TIME
        }
      end
      def select_list
        select(cols:"*", order:{play_date:"DESC", play_time:"DESC"}, limit:10)
      end
      def add(date:)
        @date = date
        exists? ? add_existing : add_new
      end
      def exists?
        select(where:{date:date.to_s}).count > 0
      end
      def add_new
        insert(values:build)
      end
      def add_existing
        update(values:build, where:{date:date.to_s})
      end
      def build
        {
          date:      date.to_s,
          play_date: Date.today.to_s,
          play_time: Time.now.strftime("%T")
        }
      end
    end
    class Scores < SQL
      def initialize
        super(table:"scores").make_table
      end
      def cols
        {
          date: :DATE,
          date_done: :DATE,
          time: :TEXT,
          reveals: :INT
        }
      end
      def add(game:)
        insert(values:build(game:game))
      end
      def select_list
        select(cols:"*", where:{reveals:0}, 
               order:{time:"ASC"}, limit:10)
      end
      def build(game:)
        {
          date:game.date.to_s,
          date_done:Date.today.to_s,
          time:game.timer.time.strftime("%T"),
          reveals:game.state.reveals
        }
      end
    end
  end
  module Windows
    class Window < Curses::Window
      include Chars
      attr_reader :y, :x, :line, :col
      attr_reader :centered_y, :centered_x
      def initialize(y:0, x:0, line:nil, col:nil)
        @y, @x = wrap_dims(y:y, x:x)
        @line,@col= center_pos(y:y,x:x,line:line,col:col)
        @centered_y, @centered_x = [line, col]
          .map{|pos| pos.nil?}
        super(@y, @x, @line, @col)
        keypad(true)
      end
      def draw(cp:$colors[:box]||0, clr:false)
        erase if clr
        setpos.color(cp)
        1.upto(y) do |i|
          line = case i
          when 1 then top_border
          when y then bottom_border
          else side_border
          end
          self << line
        end; setpos.color.noutrefresh
        self
      end
      def color(cp=0)
        color_set(cp); self
      end
      def bold(on=true)
        on ?
          attron(Curses::A_BOLD)  : 
          attroff(Curses::A_BOLD)
        self
      end
      def wrap_str(str:, line:)
        split_str(str).each_with_index do |l, i|
          setpos(line+i, 2)
          self << l
        end; self
      end
      def setpos(y=0, x=0)
        super(y,x); self
      end
      def add_str(str:,y:line,x:(@x-str.length)/2, cp:nil, bold:false)
        color(cp) if cp 
        setpos(*wrap_str_dims(y:y, x:x, str:str))
        bold(bold)
        self << str
        noutrefresh
        reset_attrs
      end
      def clear
        erase
        noutrefresh
        self
      end
      def time_str(str:, y:, x:(@x-str.length)/2, t:5, cp:nil, bold:false)
        Thread.new{
          add_str(str:str, y:y, x:x, cp:cp, bold:bold)
          sleep(t)
          add_str(str:" "*str.length, y:y, x:x, cp:cp, bold:bold)
        }
        self
      end
      def reset_attrs
        color(0).bold(false)
        self
      end
      def refresh
        super; self
      end
      def reset_pos_resize
        move(
          *[centered_y, centered_x]
          .zip(totals, [y, x], [line, col])
          .map{|cent, tot, dim, pos| cent ? (tot-dim)/2 : pos}
        )
      end
      private
      def wrap_dims(y:, x:)
        [y, x].zip(total_dims)
          .map{|dim, tot| dim <= 0 ? dim+tot : dim}
      end
      def wrap_str_dims(y:, x:, str:)
        [y, x].zip(total_dims)
          .map{|pos,tot|pos<0 ? tot-str.length+pos : pos}
      end
      def total_dims
        [Curses.lines, Curses.cols]
      end
      def center_pos(y:, x:, line:, col:)
        [line, col].zip(total_dims, [y, x])
          .map{|pos, tot, dim| pos || ((tot-dim)/2)}
      end
      def split_str(str)
        str.gsub(/(.{1,#{x-4}})(\s+|$\n?)|(.{1,#{x-4}})/, "\\1\\3\n").split("\n")
      end
      def top_border
        LU+(HL*(x-2))+RU
      end
      def bottom_border
        LL+(HL*(x-2))+RL
      end
      def side_border
        VL+(' '*(x-2))+VL
      end
    end
    class Grid < Window
      attr_reader :sq, :cells
      def initialize(y:, x:, line:nil, col:nil)
        @sq    = Pos.mk(y,x)
        @y, @x = sq_to_dims(y:y, x:x)
        super(y:@y, x:@x, line:line, col:col)
        @cells = make_cells(**sq)
      end
      def draw(cp:$colors[:grid]||0)
        setpos.color(cp)
        1.upto(y) do |i|
          line = case i
          when 1 then top_border
          when y then bottom_border
          else i.even? ? side_border : inner_border
          end
          self << line
        end; setpos.color
        self
      end
      def add_str(str:, y:0, x:0)
        str.chars.each_with_index do |char, i|
          cell(y:y, x:x+i).write(char)
        end
      end
      def cell(y:, x:)
        cells[y][x]
      end
      private
      def sq_to_dims(y:, x:)
        [ (2*y)+1, (4*x)+1 ]
      end
      def make_cells(y:, x:)
        y.times.map{|iy| x.times.map{|ix|
          Cell.new(sq:Pos.mk(iy,ix), grid:self)}}
      end
      def top_border
        LU+(HL*3+TD)*(sq[:x]-1)+HL*3+RU
      end
      def bottom_border
        LL+(HL*3+TU)*(sq[:x]-1)+HL*3+RL
      end
      def side_border
        (VL+" "*3)*sq[:x]+VL
      end
      def inner_border
        TR+(HL*3+XX)*(sq[:x]-1)+HL*3+TL
      end
    end
    class Cell
      attr_reader :sq, :grid, :pos
      def initialize(sq:, grid:)
        @sq, @grid, @pos = sq, grid, calc_abs_pos(**sq)
      end
      def focus(y:0, x:0)
        grid.setpos(*[y,x].zip(pos.values).map(&:sum))
        self
      end
      def write(char)
        focus.grid << char; self
      end
      protected
      def calc_abs_pos(y:, x:)
        { y:(2*y)+1, x:(4*x)+2 }
      end
    end
    class Bar < Window
      attr_reader :bg_col
      def initialize(line:, bg_col:$colors[:bar])
        super(y:1, x:0, line:line, col:0)
        @bg_col = bg_col
      end
      def add_str(y:0, x:, str:, bold:false, cp:bg_col)
        super(y:0, x:x, str:str, bold:bold, cp:cp)
      end
      def time_str(x:, str:, t:5, cp:bg_col, bold:false)
        super(y:0, x:x, str:str, t:5, cp:cp, bold:bold)
      end
      def draw
        bkgd(Curses.color_pair(bg_col)); self
      end
    end
  end
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
    end
    class Bottom_Bar < Windows::Bar
      def initialize
        super(line:Curses.lines-1)
      end
      def draw
        super
        noutrefresh
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
        line = (Curses.lines-15)/2
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
      def add_title(y:4, str:title, cp:$colors[:title], bold:true)
        add_str(y:y, str:str, cp:cp, bold:bold)
      end
    end
    class Resizer < Menu_Box
      attr_reader :redraw
      def initialize(redraw:nil)
        super(y:8, title:title)
        @redraw = redraw
      end
      def title
        "Screen too small"
      end
      def draw
        Screen.clear
        super
        wrap_str(str:prompt, line:5)
        refresh
        #getch
      end
      def show
        while Screen.too_small?
          draw
          getch
        end
        clear
        redraw.call if redraw
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
      attr_reader :selector
      def initialize(height:opts.length+6,
                     sel:Selector, sel_opts:opts.keys,
                     tick:nil, **)
        super(y:height, title:title)
        @selector = sel.new(opts:sel_opts, ctrls:ctrls, line:line+5, x:logo.x, tick:tick)
      end
      def title
        "Placeholder"
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
          ?j => ->{selector.cursor += 1},
          ?k => ->{selector.cursor -= 1},
          10 => ->{enter},
          ?q => ->{back},
          3 => ->{back},
          Curses::KEY_RESIZE => ->{Screen.redraw(cb:->{draw})}
        }
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
        dates.map{|d| d.to_long}
      end
      def stat_date
        dates[selector.cursor]
      end
    end
    class Yes_No_Menu < Menu
      attr_reader :yes, :no, :post_proc
      def initialize(yes:, no:->{back}, post_proc:nil)
        super
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
      attr_reader :opts
      def initialize
        set_date(date:Date.today)
        super(height:7, sel:Interface::Date_Selector)
      end
      def title
        "Select Date"
      end
      def ctrls
        super.merge({
          ?h => ->{selector.cursor -= 1},
          ?l => ->{selector.cursor += 1},
          ?j => ->{inc_date(1)},
          ?k => ->{inc_date(-1)},
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
        set_date(date:Date.today) if date_late?
        set_date(date:Date.today << 9) if date_early?
      end
      def date_late?
        stat_date > Date.today
      end
      def date_early?
        stat_date < Date.today<<9
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
  module Main
    module Windows
      class Top_Bar < Cliptic::Interface::Top_Bar
        def initialize(date:Date.today)
          super(date:date)
        end
      end
      class Bottom_Bar < Cliptic::Interface::Bottom_Bar
        def draw
          super
          add_str(x:-1, str:controls)
        end
        def mode(mode)
          setpos.color($colors[mode]) << mode_str(mode)
            .center(8)
          color.refresh
        end
        def unsaved(bool)
          add_str(x:9, str:(bool ? "| +" : "   "), bold:bool)
        end
        private
        def mode_str(mode)
          { N:"NORMAL", I:"INSERT" }[mode]
        end
        def controls
          "[^S]: Save | [^R]: Reveal | [^K]: Reset"
        end
      end
      class Grid < Cliptic::Windows::Grid
        attr_reader :indices, :blocks
        def initialize(puzzle:)
          super(**puzzle.size, line:1)
          @indices,@blocks = puzzle.indices,puzzle.blocks
          link_cells_to_clues(clues:puzzle.clues)
        end
        def draw
          super
          add_indices
          add_blocks
        end
        def cell(y:, x:)
          cells[y][x]
        end
        private
        def add_indices
          indices.each{|i,pos|cell(**pos).set_number(n:i)}
        end
        def add_blocks
          blocks.each{|pos| cell(**pos).set_block}
        end
        def make_cells(y:, x:)
          y.times.map{|iy| x.times.map{|ix| 
            Cell.new(sq:Pos.mk(iy,ix), grid:self) }}
        end
        def link_cells_to_clues(clues:)
          clues.each do |clue|
            clue.cells=clue.coords.map{|pos|cell(**pos)}
          end
        end
      end
      class Cell < Cliptic::Windows::Cell
        attr_reader :index, :blocked, :buffer
        attr_accessor :locked
        def initialize(sq:, grid:)
          super(sq:sq, grid:grid)
          @index, @blocked, @locked  = false, false, false
          @buffer = " "
        end
        def set_number(n:index, active:false)
          @index = n unless index
          grid.color(active ? 
                    $colors[:active_num] :
                    $colors[:num])
          focus(y:-1, x:-1)
          grid << Chars.small_num(n)
          grid.color
        end
        def set_block
          focus(x:-1).grid.color($colors[:block]) << Chars::Block
          @blocked = true
          grid.color
        end
        def underline
          grid.attron(Curses::A_UNDERLINE)
          write
          grid.attroff(Curses::A_UNDERLINE)
        end
        def write(char=@buffer)
          unless @locked
            super(char)
            @buffer = char
          end; self
        end
        def unlock
          @locked = false unless @blocked; self
        end
        def color(cp)
          grid.color(cp)
          write
          grid.color
        end
        def clear
          @locked, @blocked = false, false
          @buffer = " "
        end
      end
      class Cluebox < Cliptic::Windows::Window
        def initialize(grid:)
          super(y:Curses.lines-grid.y-2, line:grid.y+1, col:0)
        end
        def show(clue:)
          draw(cp:$colors[:cluebox])
          set_meta(clue)
          set_hint(clue)
          noutrefresh
        end
        private
        def set_meta(clue)
          add_str(y:0, x:2, str:clue.meta, 
                  cp:clue.done ? 
                  $colors[:correct] : $colors[:meta])
        end
        def set_hint(clue)
          wrap_str(str:clue.hint, line:1)
        end
        def bottom_border
          side_border
        end
      end
    end
    module Fetch
      class Request
        URL="https://data.puzzlexperts.com/puzzleapp-v3/data.php"
        attr_reader :data
        def initialize(date:Date.today, psid:100000160)
          @data = {date:date, psid:psid}
        end
        def send_request
          valid_input? ? raw : (raise Errors::Invalid_Date)
        end
        def valid_input?
          JSON.parse(raw, symbolize_names:true)
            .dig(:cells, 0, :meta, :data).length > 0
        end
        def raw
          @raw || Curl.get(URL, data).body
        end
      end
      class Cache < Request
        Path = "#{Dir.home}/.cache/cliptic"
        def initialize(date:Date.today)
          super(date:date)
          make_cache_dir
        end
        def query
          date_cached? ? read_cache : send_request
            .tap{|str| write_cache(str)}
        end
        def make_cache_dir
          FileUtils.mkdir_p(Path) unless Dir.exist?(Path)
        end
        def date_cached?
          File.exist?(file_path)
        end
        def file_path
          "#{Path}/#{data[:date]}"
        end
        def read_cache
          File.read(file_path)
        end
        def write_cache(str)
          File.write(file_path, str)
        end
      end
      class Parser
        attr_reader :raw
        def initialize(date:Date.today)
          @raw = Cache.new(date:date).query
        end
        def parse
          [ parse_clues(raw), parse_size(raw) ]
        end
        private
        def parse_size(raw)
          Pos.mk(*["rows", "columns"]
            .map{|field| raw.scan(/#{field}=(.*?(?=&))/)[0][0]}
          )
        end
        def parse_clues(raw)
          JSON.parse(raw, symbolize_names:true)
            .dig(:cells, 0, :meta, :data)
            .gsub(/^(.*?&){3}(.*)&id=.*$/, "\\2")
            .split(/(?:^|&).*?=/).drop(1)
            .each_slice(5).to_a
            .map{|data| Puzzle::Clue.new(**struct_clue(data))}
        end
        def struct_clue(raw_clue)
          {
              ans:raw_clue[0].chars.map(&:upcase),
             hint:CGI.unescape(raw_clue[1]),
              dir:raw_clue[2].to_sym,
            start:Pos.mk(raw_clue[3], raw_clue[4])
          }
        end
      end
    end
    module Puzzle
      class Puzzle
        include Fetch
        attr_reader :clues, :size, :indices, :map, 
          :sorted, :blocks
        def initialize(date:Date.today)
          @clues, @size = Parser.new(date:date).parse
          @indices = index_clues
          @map     = map_clues
          @sorted  = order_clues
          @blocks  = find_blocks
          chain_clues
        end
        def first_clue
          sorted[:a][0].index == 1 ?
            sorted[:a][0] : 
            sorted[:d][0]
        end
        def get_clue(y:, x:, dir:)
          map[:index][dir][y][x].is_a?(Clue) ?
            map[:index][dir][y][x] :
            map[:index][Pos.change_dir(dir)][y][x]
        end
        def get_clue_by_index(i:, dir:)
          sorted[dir]
            .find{|clue| clue.index == i} || 
          sorted[Pos.change_dir(dir)]
            .find{|clue| clue.index == i}
        end
        def complete?
          clues.all?{|c| c.done}
        end
        def n_clues_done
          clues.select{|c| c.done}.count
        end
        def n_clues
          clues.count
        end
        def check_all
          clues.each{|c| c.check}
        end
        private
        def index_clues
          clues.map{|clue| clue.start.values}.uniq.sort
            .each_with_index
            .map{ |pos, n| [n+1, Pos.mk(*pos)] }.to_h
            .each{|n, pos| clues.find_all{|clue| clue.start==pos}
            .each{|clue| clue.index = n}}
        end
        def empty
          Array.new(size[:y]){ Array.new(size[:x], ".") }
        end
        def map_clues
          { index:{a:empty, d:empty}, chars:empty }.tap do |map|
            clues.each do |clue|
              clue.coords.zip(clue.ans) do |pos, char|
                map[:index][clue.dir][pos[:y]][pos[:x]] = clue
                map[:chars][pos[:y]][pos[:x]] = char
              end
            end
          end
        end
        def order_clues
          {a:[], d:[]}.tap do |order|
            clues.map{|clue| order[clue.dir] << clue}
          end
        end
        def find_blocks
          [].tap do |a|
            map[:chars].each_with_index.map do |row, y|
              row.each_with_index.map do |char, x|
                a << Pos.mk(y,x) if char == "."
              end
            end
          end
        end
        def chain_clues
          sorted.each do |dir, clues|
            clues.each_with_index do |clue, i|
              clue.next = sorted[dir][i+1] ||
                sorted[Pos.change_dir(dir)][0]
              clue.prev = i == 0 ?
                sorted[Pos.change_dir(dir)].last :
                sorted[dir][i-1]
            end
          end
        end
      end
      class Clue
        attr_reader :ans, :dir, :start, :hint, :length, 
          :coords, :done
        attr_accessor :index, :next, :prev, :cells
        def initialize(ans:, hint:, dir:, start:)
          @ans, @dir, @start = ans, dir, start
          @length = ans.length
          @hint   = parse_hint(hint)
          @coords = map_coords(**start, l:length)
          @done   = false
        end
        def meta
          @meta || "#{index} #{dir==:a ? "across" : "down"}"
        end
        def activate
          cells.first.set_number(active:true)
          cells.each{|c| c.underline}
        end
        def deactivate
          cells.first.set_number(active:false)
          cells.each{|c| c.write}
          check if $config[:auto_mark]
        end
        def has_cell?(y:, x:)
          coords.include?(Pos.mk(y,x))
        end
        def check
          if full?
            correct? ? mark_correct : mark_incorrect
          end
        end
        def full?
          get_buffer.reject{|b| b == " "}.count == length
        end
        def clear
          cells.each{|c| c.write(" ")}
        end
        def reveal
          ans.zip(cells){|char, cell| cell.write(char)}
          mark_correct
        end
        private
        def parse_hint(hint)
          hint.match?(/^.*\(.*\)$/) ? 
            hint : "#{hint} (#{length})"
        end
        def map_coords(y:, x:, l:)
          case dir
          when :a then x.upto(x+l-1)
            .map{|ix| Pos.mk(y,ix)}
          when :d then y.upto(y+l-1)
            .map{|iy| Pos.mk(iy,x)}
          end
        end
        def get_buffer
          cells.map{|c| c.buffer}
        end
        def correct?
          get_buffer.join == ans.join
        end
        def mark_correct
          cells.each do |cell|
            cell.color($colors[:correct])
            cell.locked = true
          end
          @done = true
        end
        def mark_incorrect
          cells.each{|c| c.color($colors[:incorrect])}
        end
      end
    end
    module Player
      module Menus
        class Pause < Interface::Menu
          attr_reader :game
          def initialize(game:)
            super
            @game = game
            @draw_bars = false
          end
          def opts
            {
              "Continue" => ->{back; game.unpause},
              "Exit Game" => ->{back; game.exit}
            }
          end
          def title
            "Paused"
          end
        end
        class Puzzle_Complete < Interface::Menu
          def initialize
            super
            @draw_bars = false
          end
          def opts
            {
              "Exit" => ->{back; Screen.clear},
              "Quit" => ->{exit}
            }
          end
          def title
            "Puzzle Complete!"
          end
        end
        class Reset_Progress < Interface::Yes_No_Menu
          def initialize(game:)
            super(yes:->{game.reset},
                  post_proc:->{game.unpause})
            @draw_bars = false
          end
          def title
            "Reset puzzle progress?"
          end
        end
      end
      class Board
        include Puzzle, Windows
        attr_reader :puzzle, :grid, :box, :cursor, :clue, :dir
        def initialize(date:Date.today)
          @puzzle = Puzzle::Puzzle.new(date:date)
          @grid   = Grid.new(puzzle:puzzle)
          @box    = Cluebox.new(grid:grid)
          @cursor = Cursor.new(grid:grid)
        end
        def setup(state:nil)
          grid.draw
          load_state(state:state)
          set_clue(clue:puzzle.first_clue, mv:true)
          update
          self
        end
        def update
          cursor.reset
          grid.refresh
        end
        def redraw
          grid.draw
          grid.cells.flatten
            .find_all{|c| c.buffer != " "}
            .each{|c| c.unlock.write}
          puzzle.check_all if $config[:auto_mark]
          clue.activate
        end
        def move(y:0, x:0)
          cursor.move(y:y, x:x)
          if current_cell.blocked
            move(y:y, x:x)
          elsif outside_clue?
            set_clue(clue:get_clue_at(**cursor.pos))
          end
        end
        def insert_char(char:, advance:true)
          addch(char:char)
          move_after_insert(advance:advance)
          check_current_clue
        end
        def delete_char(advance:true)
          addch(char:" ").underline
          advance_cursor(n:-1) if advance && 
            !on_first_cell?
        end
        def next_clue(n:1)
          n.times do 
            set_clue(clue:clue.next, mv:true)
          end
          next_clue if clue.done && !puzzle.complete?
        end
        def prev_clue(n:1)
          n.times do 
            on_first_cell? ?
              set_clue(clue:clue.prev, mv:true) :
              to_start
          end
          prev_clue if clue.done && !puzzle.complete?
        end
        def to_start
          cursor.set(**clue.coords.first)
        end
        def to_end
          cursor.set(**clue.coords.last)
        end
        def swap_direction
          set_clue(clue:get_clue_at(
            **cursor.pos, dir:Pos.change_dir(dir)))
        end
        def save_state
          [].tap do |state|
            grid.cells.flatten.map do |cell|
              state << { sq:cell.sq, char:cell.buffer } unless cell.blocked || cell.buffer == " "
            end
          end
        end
        def goto_clue(n:)
          set_clue(clue:get_clue_by_index(i:n), mv:true)
        end
        def goto_cell(n:)
          if n > 0 && n <= clue.length
            cursor.set(**clue.cells[n-1].sq)
          end
        end
        def clear_clue
          clue.clear
          clue.activate
        end
        def reveal_clue
          clue.reveal
          next_clue(n:1)
        end
        def clear_all_cells
          grid.cells.flatten.each{|c| c.clear}
        end
        def advance_cursor(n:1)
          case dir
          when :a then move(x:n)
          when :d then move(y:n)
          end
        end
        private
        def load_state(state:)
          if state.exists?
            state.chars.each do |s|
              grid.cell(**s[:sq]).write(s[:char])
            end
            puzzle.check_all if $config[:auto_mark]
          end
        end
        def set_clue(clue:, mv:false)
          @clue.deactivate if @clue
          @clue = clue
          @dir  = clue.dir
          clue.activate
          cursor.set(**clue.start.dup) if mv
          box.show(clue:clue)
        end
        def current_cell
          grid.cell(**cursor.pos)
        end
        def on_first_cell?
          current_cell == clue.cells.first
        end
        def on_last_cell?
          current_cell == clue.cells.last
        end
        def outside_clue?
          !clue.has_cell?(**cursor.pos)
        end
        def get_clue_at(y:, x:, dir:@dir)
          puzzle.get_clue(y:y, x:x, dir:dir)
        end
        def get_clue_by_index(i:)
          puzzle.get_clue_by_index(i:i, dir:dir)
        end
        def addch(char:)
          current_cell.write(char.upcase)
        end
        def move_after_insert(advance:)
          if on_last_cell?
            next_clue(n:1) if $config[:auto_advance]
          elsif advance
            advance_cursor(n:1)
          end
        end
        def check_current_clue
          clue.check if $config[:auto_mark]
        end
      end
      class Cursor
        attr_reader :grid, :pos
        def initialize(grid:)
          @grid = grid
        end
        def set(y:, x:)
          @pos = Pos.mk(y,x)
        end
        def reset
          grid.cell(**pos).focus
          Curses.curs_set(1)
        end
        def move(y:, x:)
          @pos[:y]+= y
          @pos[:x]+= x
          wrap
        end
        def wrap
          pos[:x] += 15 while pos[:x] < 0
          pos[:y] += 15 while pos[:y] < 0
          pos[:x] -= 15 while pos[:x] > 14
          pos[:y] -= 15 while pos[:y] > 14
        end
      end
      class Game
        include Database, Windows, Menus
        attr_reader :state, :board, :top_b, :timer, 
          :bot_b, :ctrls , :date
        attr_accessor :mode, :continue, :unsaved
        def initialize(date:Date.today)
          @date  = date
          @state = State.new(date:date)
          @board = Board.new(date:date)
          @top_b = Top_Bar.new(date:date)
          @bot_b = Bottom_Bar.new
          @timer = Timer.new(time:state.time, bar:top_b, 
                             callback:->{board.update})
          @ctrls = Controller.new(game:self)
          @unsaved  = false
          @continue = true
          setup
        end
        def play
          if state.done
            show_completed_menu
          else
            add_to_recents
            game_and_timer_threads.map(&:join)
          end
        end
        def setup
          [top_b, bot_b].each(&:draw)
          self.mode = :N
          board.setup(state:state)
        end
        def unsaved=(bool)
          @unsaved = bool
          bot_b.unsaved(bool)
        end
        def mode=(mode)
          @mode = mode
          bot_b.mode(mode)
        end
        def user_input
          board.grid.getch
        end
        def pause
          timer.stop
          Menus::Pause.new(game:self).choose_opt
        end
        def unpause
          timer.start
          board.redraw
        end
        def save
          state.save(game:self)
          bot_b.time_str(t:5, x:10, str:"Saved!")
          self.unsaved = false
        end
        def reset_menu
          timer.stop
          Reset_Progress.new(game:self)
        end
        def reset
          state.delete if state.exists?
          board.clear_all_cells
          timer.reset
        end
        def reveal
          state.reveals+= 1
          board.reveal_clue
        end
        def game_over
          save if $config[:auto_save]
          timer.stop
          completed if board.puzzle.complete?
        end
        def exit
          @continue = false
          Screen.clear
        end
        private
        def completed
          save
          log_score
          show_completed_menu
        end
        def run
          until game_finished?
            ctrls.route(char:user_input)&.call
            board.update
          end
          game_over
        end
        def game_finished?
          board.puzzle.complete? || !continue
        end
        def game_and_timer_threads
          [ Thread.new{run}, Thread.new{timer.start} ]
        end
        def show_completed_menu
          Puzzle_Complete.new.choose_opt
        end
        def add_to_recents
          Recents.new.add(date:date)
        end
        def log_score
          Scores.new.add(game:self)
        end
      end
      class Timer
        attr_reader :time, :bar, :callback, :run
        def initialize(time:0, bar:, callback:)
          @time = Time.abs(time)
          @bar, @callback = bar, callback
        end
        def start
          Thread.new{tick}
          @run = true
        end
        def stop
          @run = false
        end
        def reset
          @time = Time.abs(0)
          @run = false
        end
        private
        def tick
          while @run
            bar.add_str(x:-1, str:time_str)
            callback.call
            @time += 1
            sleep(1)
          end
        end
        def time_str
          time.strftime("%T")
        end
      end
      class Controller
        attr_reader :game
        def initialize(game:)
          @game = game
        end
        def route(char:)
          if is_ctrl_key?(char)
            controls[:G][char.to_i]
          else
            case game.mode
            when :N then normal(char:char)
            when :I then insert(char:char)
            end
          end
        end
        def normal(char:, n:1)
          if (?0..?9).cover?(char)
            await_int(n:char.to_i)
          else
            controls(n)[:N][char]
          end
        end
        def insert(char:)
          case char
          when 27  then ->{game.mode = :N}
          when 127 then ->{game.board.delete_char}
          when ?A..?z 
            ->{game.board.insert_char(char:char);
               game.unsaved = true }
          end
        end
        def is_ctrl_key?(char)
          (1..26).cover?(char)
        end
        def controls(n=1)
          {
            G:{
              3  => ->{game.exit},
              5  => ->{game.reset_menu.choose_opt},
              9  => ->{game.board.swap_direction},
              18 => ->{game.reveal},
              19 => ->{game.save},
              16 => ->{game.pause}
            },
            N:{
              ?j => ->{game.board.move(y:n)},
              ?k => ->{game.board.move(y:n*-1)},
              ?h => ->{game.board.move(x:n*-1)},
              ?l => ->{game.board.move(x:n)},
              ?i => ->{game.mode = :I},
              ?w => ->{game.board.next_clue(n:n)},
              ?a => ->{game.board.advance_cursor(n:1); game.mode=:I},
              ?b => ->{game.board.prev_clue(n:n)},
              ?e => ->{game.board.to_end},
              ?r => ->{await_replace},
              ?c => ->{await_delete; game.mode=:I},
              ?d => ->{await_delete},
              ?x => ->{game.board.delete_char(advance:false)}
            }
          }
        end
        def await_int(n:)
          char = game.user_input
          case char
          when ?g then ->{game.board.goto_clue(n:n)}
          when ?G then ->{game.board.goto_cell(n:n)}
          when ?0..?9 then await_int(n:(10*n)+char.to_i)
          else normal(char:char, n:n)
          end
        end
        def await_replace
          char = game.user_input 
          case char
          when ?A..?z 
            game.board.insert_char(
              char:char, advance:false)
          end
        end
        def await_delete
          case game.user_input
          when ?w then game.board.clear_clue
          end
        end
      end
    end
  end
  class Wrapper
    def self.run
      Screen.setup
      Config::Setter.new.set
      Menus::Main.new.choose_opt
    end
  end
end

Cliptic::Wrapper.run
#Cliptic::Screen.setup
#Cliptic::Config::Setter.new.set
#Cliptic::Menus::Main.new.choose_opt
#Cliptic::Main::Player::Game.new.play
