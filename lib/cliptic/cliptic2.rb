require 'cgi'
require 'curb'
require 'curses'
require 'date'
require 'fileutils'
require 'json'
require 'sqlite3'
require 'time'

#require_relative "cliptic/version"

$colors = {
  box:4, grid:8, bar:16, logo_grid:8, logo_text:1, title:1, stats:4
}

module Cliptic
  class Pos
    def self.mk(y,x)
      { y:y.to_i, x:x.to_i }
    end
    def self.wrap(val:, min:, max:)
      val > max ? min : (val < min ? max : val)
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
  end
  module Config
    Dir_Path  = "#{Dir.home}/.config/cliptic"
    File_Path = "#{Dir_Path}/cliptic.rc"
    class Default
      def self.colors
        {
          box:4, grid:8, bar:16, logo_grid:8, 
          logo_text:1, title:1, stats:4
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

    end
    class Reader

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
    class States < SQL
      include Chars
      attr_reader :date, :time, :chars, :n_done, :n_tot,
        :reveals, :done
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
      def exists?
        @exists || query.count > 0
      end
      def query
        @query || select(where:{date:date})
      end
      def parse_chars(str)
        JSON.parse(str, symbolize_names:true)
      end
    end
    class Stats < States
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
        <<~stats

          Not attempted

        stats
      end
    end
    class Recents < SQL
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
        select(cols:"*", order:{play_date:"ASC", play_time:"ASC"}, limit:10)
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

      end
      def select_list
        select(cols:"*", where:{reveals:0}, 
               order:{time:"ASC"}, limit:10)
      end
    end
  end
  module Windows
    class Window < Curses::Window
      include Chars
      attr_reader :y, :x, :line, :col
      def initialize(y:, x:, line:nil, col:nil)
        @y, @x = wrap_dims(y:y, x:x)
        @line, @col = center_pos(y:y, x:x, line:line, col:col)
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
        }.join
        self
      end
      def reset_attrs
        color(0).bold(false)
        self
      end
      def refresh
        super; self
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
    class Menu_Box < Windows::Window
      include Interface
      attr_reader :logo, :title, :top_b, :bot_b
      def initialize(y:, title:false)
        line = (Curses.lines-15)/2
        @logo = Logo.new(line:line+1)
        @title = title
        super(y:y, x:logo.x+4, line:line, col:nil)
        @top_b = Top_Bar.new
        @bot_b = Bottom_Bar.new
      end
      def draw
        super
        [top_b, bot_b, logo].each(&:draw)
        add_title if title
        self
      end
      def add_title(y:4, str:title, cp:$colors[:title], bold:true)
        add_str(y:y, str:str, cp:cp, bold:bold)
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
                     tick:nil)
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
          ?q => ->{back}
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
        puts "Hello" + stat_date.to_s
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
  end
  module Menus
    class Main < Interface::Menu
      def opts
        {
          "Play Today" => ->{exit},
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
        @opts || days.map{|d| d.strftime("%A")}
      end
      def title
        "This Week"
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
  module Player
    module Windows
      class Top_Bar < Cliptic::Interface::Top_Bar

      end
      class Bottom_Bar < Cliptic::Interface::Bottom_Bar

      end
      class Grid < Cliptic::Windows::Grid

      end
      class Cell < Cliptic::Windows::Cell

      end
      class Cluebox < Cliptic::Windows::Window

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
        attr_reader :clues, :size, :indices, :map
        def initialize(date:Date.today)
          @clues, @size = Parser.new(date:date).parse
          @indices = index_clues
          @map     = map_clues
          @sorted  = sort_clues
          @blocks  = find_blocks
          chain_clues
        end
        private
        def index_clues
          clues.map{|clue| clue.start.values}.uniq.sort
            .each_with_index
            .map{ |pos, n| [n+1, Pos.mk(*pos)] }.to_h
            .each{|n, pos| clues.find_all{|clue| clue.start==pos}}
            .each{|clue| clue.index = n}
        end
        def empty
          Array.new(size[:y]){ Array.new(size[:x], ".") }
        end
        def map_clues
          { index:{a:empty, d:empty}, chars:{empty} }.tap do |map|
            clues.each do |clue|
              clue.coords.zip(clue.ans) do |pos, char|
                map[:index][clue.dir][pos[:y]][pos[:x]] = clue
                map[:chars][pos[:y]][pos[:x]] = char
              end
            end
          end
        end
        def sort_clues

        end
        def chain_clues

        end
      end
      class Clue
        def initialize(ans:, hint:, dir:, start:)

        end
      end
    end
    module Game

    end
  end
end

#Cliptic::Screen.setup
#Cliptic::Menus::Main.new.choose_opt
puts Cliptic::Player::Puzzle::Puzzle.new.inspect
