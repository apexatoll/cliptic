module Cliptic
  module Windows
    class Window < Curses::Window
      include Cliptic::Chars
      attr_reader :y, :x, :line, :col, :cent_y, :cent_x
      attr_reader :prev
      def initialize(y:0, x:0, line:nil, col:nil)
        @y, @x = wrap_dimensions(y:y, x:x)
        @line,@col=center_win(y:y,x:x,line:line,col:col)
        @cent_y, @cent_x=[line, col].map{|pos| pos.nil?}
        super(@y, @x, @line, @col)
        keypad(true)
      end
      def draw(color:$colors[:box]||0)
        setpos.color(color)
        1.upto(y) do |i|
          line = case i
          when 1 then top
          when y then bottom
          else sides
          end
          self << line
        end; self
      end
      def setpos(y=0, x=0)
        super(y,x); self
      end
      def refresh
        super; self
      end
      def color(cp=0)
        color_set(cp); self
      end
      def bold(on=true)
        on ? 
          attron(Curses::A_BOLD) :
          attroff(Curses::A_BOLD)
        self
      end
      def add_wrapped(str:, line:)
        wrap(str).each_with_index do |l, i|
          setpos(line+i, 2)
          self << l
        end
      end
      def standout
        color($colors[:menus]) || super
      end
      def standend
        color(0)
      end
      private
      def totals
        [Curses.lines, Curses.cols]
      end
      def wrap_dimensions(y:, x:)
        [y, x].zip(totals)
          .map{|dim, tot| dim <= 0 ? dim + tot : dim}
      end
      def center_win(y:, x:, line:, col:)
        [line,col].zip([y,x], totals)
          .map{|pos, dim, tot| pos || ((tot-dim)/2)}
      end
      def top
        LU+(HL*(x-2))+RU
      end
      def bottom
        LL+(HL*(x-2))+RL
      end
      def sides
        VL+(" "*(x-2))+VL
      end
      def wrap(str)
        str.gsub(/(.{1,#{x-4}})(\s+|$\n?)|(.{1,#{x-4}})/, "\\1\\3\n").split("\n")
      end
    end
    class Grid < Window
      attr_reader :sq, :dims, :cells
      def initialize(y:, x:, line:nil, col:nil)
        @sq   = Pos.mk(y,x)
        @dims = Pos.sq_to_dims(y:y, x:x)
        super(**dims, line:line, col:col)
        @cells = make_cells(**sq)
      end
      def draw(color:$colors[:grid]||0)
        setpos.color(color)
        1.upto(dims[:y]) do |i|
          line = case i
          when 1 then top
          when dims[:y] then bottom
          else i.even? ? sides : inner
          end
          self << line
        end
        color
      end
      private
      def make_cells(y:, x:)
        y.times.map{|iy| x.times.map{|ix|
          Cell.new(sq:Pos.mk(iy,ix), grid:self)}}
      end
      def top
        LU+(HL*3+TD)*(sq[:x]-1)+HL*3+RU
      end
      def bottom
        LL+(HL*3+TU)*(sq[:x]-1)+HL*3+RL
      end
      def sides
        (VL+" "*3)*sq[:x]+VL
      end
      def inner
        TR+(HL*3+XX)*(sq[:x]-1)+HL*3+TL
      end
    end
    class Cell
      include Chars
      attr_reader :sq, :grid, :pos
      def initialize(sq:, grid:)
        @sq, @grid, @pos = sq, grid, Pos.sq_to_abs(**sq)
      end
      def focus(y:0, x:0)
        grid.setpos(*[y,x].zip(pos.values).map(&:sum))
        self
      end
      def write(char)
        focus.grid << char
        self
      end
    end
    class Bar < Window
      attr_reader :bg
      def initialize(line:, bg:16)
        super(y:1, x:0, line:line, col:0)
        @bg = bg
      end
      def add(x:, str:, b:false)
        setpos(0, x<0 ? Curses.cols-str.length+x : x)
        bold(true) if b
        self << str
        bold(false)
        refresh
      end
      def draw
        bkgd(Curses.color_pair(bg))
        refresh
      end
    end
    class Top_Bar < Bar
      attr_reader :date
      def initialize(date:Date.today)
        super(line:0)
        @date = date
      end
      def draw
        super
        add(x:1, str:title, b:true)
        add(x:title.length+1, str:date.to_long)
        self
      end
      def title
        "cliptic: "
      end
    end
    class Bottom_Bar < Bar
      def initialize
        super(line:Curses.lines-1)
      end
      def draw
        super; self
      end
      def mode(mode)
        setpos.color($colors[mode]) << mode_str(mode)
          .center(8)
        color.refresh
      end
      def mode_str(mode)
        {N:"NORMAL", I:"INSERT"}[mode]
      end
    end
    class Logo < Grid
      attr_reader :text
      def initialize(text:Logo_Text, line:Logo_Line)
        @text = text
        super(y:1, x:text.length, line:line)
      end
      def draw
        super(color:$colors[:logo_grid]||0)
        bold.color($colors[:logo_text]||0)
        cells.flatten.zip(text.chars) do |cell, char|
          cell.write(char)
        end
        refresh.color.bold(false)
      end
    end
    class Selector < Window
      attr_reader :opts, :ctrl, :tick, :run
      attr_accessor :cursor
      def initialize(opts:, ctrl:, tick:nil,
                     y:opts.length, x:Menu_Width, 
                     line:Menu_Line, col:nil)
        super(y:y, x:x, line:line, col:col)
        @opts, @ctrl, @tick = opts, ctrl, tick
        @cursor, @run = 0, true
      end
      def select
        while @run
          draw
          ctrl[getch]&.call
        end
      end
      def stop(cb:nil)
        @run = false
        cb.call if cb
      end
      def enter(pre:nil, post:nil)
        pre.call if pre
        opts.values[cursor].call
        post.call if post
      end
      def draw
        setpos
        (opts.keys rescue opts).each_with_index do |opt, i|
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
      def cursor=(n)
        @cursor = n
        @cursor = opts.length - 1 if cursor < 0
        @cursor = 0 if cursor >= opts.length
      end
    end
    class Date_Selector < Selector
      def initialize(opts:, ctrl:, tick:false, line:)
        super(y:1, x:18, opts:opts, ctrl:ctrl, tick:tick, line:line)
      end
      def format_opt(opt)
        opt.to_s.rjust(2, "0").center(6)
      end
    end
    class Stats < Window
      def initialize(y:5, x:Menu_Width+4, line:)
        super(y:y, x:x, line:line)
      end
      def show(date:)
        erase
        draw
        build(state(date:date)).each_with_index do |line, i|
          setpos(1+i, 8)
          self << line
        end
        refresh
      end
      def build(state)
        state.exists ? 
          [
            "Time  #{VL} #{Time.abs(state.time).to_s}",
            "Clues #{VL} #{state.n_done}/#{state.n_tot}",
            "Done  #{VL} [#{state.done ? Tick : " "}]"
          ] :
          [ "", "  Not attempted", "" ]
      end
      def state(date:)
        Database::State.new(date:date)
      end
    end
  end
end
