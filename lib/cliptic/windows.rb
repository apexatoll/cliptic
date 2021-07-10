module Cliptic
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
          .zip(total_dims, [y, x], [line, col])
          .map{|cent, tot, dim, pos| cent ? (tot-dim)/2 : pos}
        )
        refresh
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
end
