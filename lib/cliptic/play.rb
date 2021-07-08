module Cliptic
  module Play
    module Screens
      class Grid < Windows::Grid
        attr_reader :indices, :blocks
        def initialize(y:, x:)
          super(y:y, x:x, line:1)
        end
        def cell(y:, x:)
          cells[y][x]
        end
        def draw
          super
          indices.each{|i, pos| cell(**pos).set_number(n:i)}
          blocks.each{|pos| cell(**pos).set_block}
        end
        def make_cells(y:, x:)
          y.times.map{|iy| x.times.map{|ix| 
            Cell.new(sq:Pos.mk(iy,ix), grid:self) }}
        end
        def link(puzzle:)
          @indices = puzzle.indices
          @blocks  = puzzle.blocks
          [:a, :d].each do |dir|
            puzzle.clues[dir].each do |clue|
              clue.cells = clue.coords.map{|pos| cell(**pos)}
            end
          end; self
        end
      end
      class Cell < Windows::Cell
        attr_accessor :locked, :blocked, :buf, :index
        def initialize(sq:, grid:)
          super(sq:sq, grid:grid)
          @locked, @blocked = false, false
          @buf = " "
        end
        def set_block
          focus(x:-1).grid.color($colors[:block]) << Block
          @blocked = true
          grid.color
        end
        def set_number(n:index, active:false)
          @index = n unless @index
          grid.color(active ? 
            $colors[:active_num] : 
            $colors[:num] )
          focus(y:-1, x:-1)
          (grid << Chars.small_num(n)).color
          self
        end
        def color(cp)
          grid.color(cp)
          write
          grid.color
        end
        def underline
          grid.attron(Curses::A_UNDERLINE)
          write
          grid.attroff(Curses::A_UNDERLINE)
        end
        def write(char=@buf)
          unless @locked
            super(char)
            @buf = char
          end; self
        end
        def unlock
          @locked = false unless @blocked
          self
        end
      end
      class Cluebox < Windows::Window
        def initialize(grid:)
          super(y:Curses.lines-grid.dims[:y]-2, 
                line:grid.dims[:y]+1, col:0)
        end
        def show(clue:)
          draw
          set_meta(clue)
          set_hint(clue)
          noutrefresh
        end
        private
        def set_meta(clue)
          setpos(0, 2)
          color(clue.done ? 
                $colors[:correct] : 
                $colors[:meta] )
          self << clue.meta
          color
        end
        def set_hint(clue)
          color($colors[:correct]) if clue.done
          add_wrapped(str:clue.hint, line:1)
          color
        end
        def bottom
          sides
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
        def send
          valid? ? str : (raise Errors::Invalid_Date)
        end
        def valid?
          JSON.parse(str)['cells'][0]['meta']['data'].length > 0
        end
        def str
          @str || Curl.get(URL, data).body
        end
      end
      class Cache < Request
        Path = "#{Dir.home}/.cache/cliptic"
        attr_reader :date
        def initialize(date:Date.today)
          super(date:date)
          create_dir
        end
        def query
          cached? ? read : send.tap{|str| write(str)}
        end
        private
        def file_path
          "#{Path}/#{data[:date]}"
        end
        def cached?
          File.exist?(file_path)
        end
        def create_dir
          mkdir_p(Path) unless Dir.exist?(Path)
        end
        def read
          File.read(file_path)
        end
        def write(str)
          File.write(file_path, str)
        end
      end
      class Parser
        attr_reader :raw
        def initialize(date:Date.today)
          @raw = Cache.new(date:date).query
        end
        def parse
          [parse_size(raw), parse_clues(raw)]
        end
        private
        def parse_size(str)
          Pos.mk(*["rows", "columns"]
            .map{|f| str.scan(/#{f}=(.*?(?=&))/)[0][0]}
          )
        end
        def parse_clues(str)
          JSON.parse(str)['cells'][0]['meta']['data']
            .gsub(/^(.*?&){3}(.*)&id=.*$/, "\\2")
            .split(/(?:^|&).*?=/).drop(1)
            .each_slice(5).to_a
            .map{|raw| Clue.new(**make_clue(raw))}
        end
        def make_clue(raw_clue)
          {
             ans:raw_clue[0].chars.map(&:upcase),
            hint:CGI.unescape(raw_clue[1]),
             dir:raw_clue[2].to_sym,
             pos:Pos.mk(raw_clue[3], raw_clue[4])
          }
        end
      end
    end
    class Puzzle
      include Fetch
      attr_reader :size, :clues, :indices, :numbs, 
        :chars, :blocks
      def initialize(date:Date.today)
        @size, @clues = Parser.new(date:date).parse
        @indices= index_clues 
        @numbs, @chars = map_clues
        @clues  = order_clues
        @blocks = find_blocks
        link_clues_to_clues
      end
      def first_clue
        clues[:a][0].index == 1 ? 
          clues[:a][0] : clues[:d][0]
      end
      def complete?
        clues[:a].all?{|c| c.done} &&
        clues[:d].all?{|c| c.done}
      end
      def get_clue(y:, x:, dir:)
        numbs[dir][y][x].is_a?(Clue) ?
          numbs[dir][y][x] :
          numbs[Pos.change_dir(dir)][y][x]
      end
      def check_all
        clues[:a].each{|clue| clue.check}
        clues[:d].each{|clue| clue.check}
      end
      def n_done
        clues[:a].select{|c| c.done }.count + 
        clues[:d].select{|c| c.done }.count 
      end
      def n_total
        @total || clues[:a].count + clues[:d].count
      end
      private
      def empty
        Array.new(size[:y]){ Array.new(size[:x], ".") }
      end
      def index_clues
        clues.map{|clue| clue.pos.values }.uniq.sort
          .each_with_index
          .map{ |pos, n| [n+1, Pos.mk(*pos)] }.to_h
          .each{|n, pos| clues.find_all{|c| c.pos==pos }
          .each{|c| c.index = n}}
      end
      def map_clues
        [{a:empty, d:empty}, empty].tap do |numbs, chars|
          clues.each do |clue|
            clue.coords.zip(clue.ans) do |pos, char|
              numbs[clue.dir][pos[:y]][pos[:x]] = clue
              chars[pos[:y]][pos[:x]] = char
            end
          end
        end
      end
      def order_clues
        {a:[], d:[]}.tap do |order|
          clues.map{|clue| order[clue.dir] << clue }
        end
      end
      def link_clues_to_clues
        [:a, :d].each do |dir|
          clues[dir].each_with_index do |clue, i|
            clue.next = clues[dir][i+1] || 
              clues[Pos.change_dir(dir)][0]
            clue.prev = i == 0 ? 
              clues[Pos.change_dir(dir)].last :
              clues[dir][i-1]
          end
        end
      end
      def find_blocks
        [].tap do |a|
          chars.each_with_index.map do |row, y|
            row.each_with_index.map do |char, x|
              a << Pos.mk(y,x) if char == "."
            end
          end
        end
      end
    end
    class Clue
      attr_reader :ans, :dir, :hint, :pos, :length, :coords, :done
      attr_accessor :index, :next, :prev, :cells
      def initialize(ans:, hint:, dir:, pos:)
        @ans, @dir, @pos = ans, dir, pos
        @length = ans.length
        @hint   = parse_hint(hint)
        @coords = map_coords(**pos, l:length)
        @done   = false
      end
      def activate
        cells.first.set_number(active:true)
        cells.each{|cell| cell.underline}
      end
      def deactivate
        cells.first.set_number(active:false)
        cells.each{|cell| cell.write}
        check
      end
      def has?(y:, x:)
        coords.include?(Pos.mk(y,x))
      end
      def check
        if full?
          correct? ? mark_correct : mark_incorrect
        end
      end
      def full?
        get_buf.reject{|buf| buf == " "}.count == length
      end
      def meta
        @meta || " #{index} #{
          dir == :a ? "across" : "down"} "
      end
      def clear
        cells.each{|cell| cell.write(" ")}
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
        when :a then x.upto(x+l-1).map{|ix| Pos.mk(y,ix)}
        when :d then y.upto(y+l-1).map{|iy| Pos.mk(iy,x)}
        end
      end
      def get_buf
        cells.map{|c| c.buf }
      end
      def correct?
        get_buf.join == ans.join
      end
      def mark_correct
        cells.each do |c|
          c.color($colors[:correct])
          c.locked = true
        end
        @done = true
      end
      def mark_incorrect
        cells.each{|c| c.color($colors[:incorrect])}
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
        pos[:x] += 15 if pos[:x] < 0
        pos[:y] += 15 if pos[:y] < 0
        pos[:x] -= 15 if pos[:x] > 14
        pos[:y] -= 15 if pos[:y] > 14
      end
    end
    class Board
      include Screens
      attr_reader :puzzle, :grid, :cursor, :cluebox
      attr_reader :clue, :dir 
      def initialize(date:Date.today)
        @puzzle  = Puzzle.new(date:date)
        @grid    = Grid.new(**puzzle.size)
          .link(puzzle:puzzle)
        @cursor  = Cursor.new(grid:grid)
        @cluebox = Cluebox.new(grid:grid)
      end
      def setup(state:)
        grid.draw
        load_state(state:state)
        set_clue(clue:puzzle.first_clue, mv_cursor:true)
        update
      end
      def redraw
        grid.draw
        grid.cells.flatten.find_all{|c| c.buf != " "}
          .each{|c| c.unlock.write}
        puzzle.check_all if $config[:auto_mark]
        clue.activate
      end
      def update
        cursor.reset
        grid.refresh
      end
      def move(y:0, x:0)
        cursor.move(y:y, x:x)
        if current_cell.blocked
          move(y:y, x:x)
        elsif !clue.has?(**cursor.pos)
          set_clue(clue:get_clue(**cursor.pos))
        end
      end
      def insert(char:, advance:true)
        current_cell.write(char.upcase)
        if last_cell?
          next_clue #if $config[:auto_advance]
        elsif advance then advance(n:1)
        end
        clue.check #if $config[:auto_mark]
      end
      def delete(advance:true)
        current_cell.write(" ").underline
        advance(n:-1) if advance && !first_cell?
      end
      def next_clue(n:1)
        n.times{set_clue(clue:clue.next, mv_cursor:true)}
        next_clue(n:1) if clue.done && !puzzle.complete?
      end
      def prev_clue(n:1)
        n.times do 
          first_cell? ?
            set_clue(clue:clue.prev, mv_cursor:true) :
            to_start
        end
        prev_clue(n:1) if clue.done && !puzzle.complete?
      end
      def to_start
        cursor.set(**clue.coords.first)
      end
      def to_end
        cursor.set(**clue.coords.last)
      end
      def save_state
        [].tap do |array|
          grid.cells.flatten.map do |cell|
            array << { sq:cell.sq, char:cell.buf } unless cell.blocked || cell.buf == " "
          end
        end
      end
      def change_dir
        set_clue(clue:get_clue(
          **cursor.pos, dir:Pos.change_dir(dir)))
      end
      def clear_clue
        clue.clear
        clue.activate
      end
      def reveal_clue
        clue.reveal
        next_clue(n:1)
      end
      def goto_clue(n:)
        set_clue(clue:get_clue_by_index(i:n), mv_cursor:true)
      end
      def goto_cell(n:)
        if n > 0 && n <= clue.length
          cursor.set(**clue.cells[n-1].sq) 
        end
      end
      def get_clue_by_index(i:)
        (puzzle.clues[:a] + puzzle.clues[:d]).find{|c| c.index == i} || clue
      end
      private
      def load_state(state:)
        if state.exists
          state.chars.each do |data|
            grid.cell(**data[:sq]).write(data[:char])
          end 
          puzzle.check_all if $config[:auto_mark]
        end
      end
      def set_clue(clue:, mv_cursor:false)
        @clue.deactivate if @clue
        @clue = clue
        @dir  = clue.dir
        clue.activate
        cursor.set(**clue.pos.dup) if mv_cursor
        cluebox.show(clue:clue)
      end
      def get_clue(y:, x:, dir:@dir)
        puzzle.get_clue(y:y, x:x, dir:dir)
      end
      def current_cell
        grid.cell(**cursor.pos)
      end
      def last_cell?
        current_cell == clue.cells.last
      end
      def first_cell?
        current_cell == clue.cells.first
      end
      def advance(n:1)
        case dir
        when :a then move(x:n)
        when :d then move(y:n)
        end
      end
    end
    class Timer
      attr_reader :time, :bar, :board, :run
      def initialize(time:0, bar:, board:)
        @time, @bar, @board = Time.abs(time), bar, board
        @run = true
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
      end
      private
      def tick
        while run
          bar.add(x:-1, str:time.strftime("%T"))
          board.update
          @time += 1
          sleep(1)
        end
      end
    end
    class Game
      Esc = 27; Tab = 9; BS  = 127
      include Windows, Database, Menus
      attr_reader :date, :board, :mode, :continue, :top, :bottom, :timer, :state, :reveals
      def initialize(date:Date.today)
        @date     = date
        @board    = Board.new(date:date)
        @top      = Top_Bar.new(date:date)
        @bottom   = Bottom_Bar.new
        @state    = State.new(date:date)
        @timer    = Timer.new(time:state.time, 
                              bar:top, board:board)
        @reveals  = state.reveals.dup
        @continue = true
      end
      def run
        setup
        if state.done
          Puzzle_Complete.new.select
        else
          Recents.new.add(date:date)
          @game = Thread.new{play}
          @time = Thread.new{timer.start}
          @thrd = [@game, @time].map(&:join)
        end
      end
      def play
        until finished?
          char = board.grid.getch
          case char
          when 1..26 then global(char)
          else case @mode
            when :N then Controller.normal(char:char)&.call(self) #normal(char:char)
            when :I then insert(char).call(char)
            end
          end#&.call(char)
          board.update
        end
        quit
      end
      def unpause
        timer.start
        top.draw
        bottom.draw
        bottom.mode(@mode)
        board.redraw
      end
      def hard_quit
        Screen.clear
        @continue = false
      end
      def mode=(mode)
        @mode = mode
        bottom.mode(mode)
      end
      protected
      def setup
        top.draw
        bottom.draw
        self.mode = :N
        board.setup(state:state)
      end
      def finished?
        board.puzzle.complete? || !continue
      end
      def global(char)
        case char
        when 19 then ->(_){save}
        when 3  then ->(_){hard_quit}
        when 9 then ->(_){board.change_dir}
        when 16 then ->(_){pause}
        when 18 then ->(_){board.reveal_clue}
        when 2  then ->(_){reset_menu.select}
        end
      end
      def normal(char:, n:1)
        case char
        when ?0..?9
          await_int(char.to_i)
        else
          {
            ?j => ->(_){board.move(y:n)},
            ?k => ->(_){board.move(y:n*-1)},
            ?h => ->(_){board.move(x:n*-1)},
            ?l => ->(_){board.move(x:n)},
            ?i => ->(_){self.mode = :I},
            ?w => ->(_){board.next_clue(n:n)},
            ?b => ->(_){board.prev_clue(n:n)},
            ?e => ->(_){board.to_end},
            ?c => ->(_){await_clear&.call;self.mode=:I},
            ?d => ->(_){await_clear&.call},
            ?r => ->(_){await_replace&.call}
          }[char]
        end
      end
      def insert(char)
        case char
        when Esc then ->(_){self.mode=:N}
        when BS  then ->(_){board.delete}
        when ?A..?z then ->(c){board.insert(char:c)}
        end
      end
      def await_clear
        char = board.grid.getch
        case char
        when ?w then ->{board.clear_clue}
        end
      end
      def await_int(n)
        char = board.grid.getch
        case char
        when ?0..?9 then await_int((10*n)+char.to_i)
        when ?g then board.goto_clue(n:n)
        when ?G then board.goto_cell(n:n)
        else normal(char:char, n:n)
        end
      end
      def await_replace
        char = board.grid.getch 
        case char
        when ?A..?z then ->{board.insert(char:char, advance:false)}
        end
      end
      def reset_menu
        timer.stop
        Yes_No.new(
          prompt:"Reset progress?", 
          yes:->{puts "hello"}, 
          post:->{unpause}
        )
      end
      def pause
        timer.stop
        Pause.new(game:self).select
      end
      def save
        state.save(game:self)
      end
      def quit
        save if $config[:auto_save]
        timer.stop
        completed if board.puzzle.complete?
      end
      def completed
        save
        Scores.new.add(game:self)
        Puzzle_Complete.new.select
      end
    end
    class Controller
      def self.normal(char:, n:1)
        if [*(?0..?9)].include?(char)
          await_int(n:char.to_i)
        else
          commands(n:n)[:N][char]
        end
        #if 
        #await_int(n:char.to_i) if [?0..?9].include?(char)
        #{
          #[]
          #?b => ->(g){ g.board.prev_clue(n:n)},
          #?c => ->(g){ g.await_clear&.call;self.mode=:I},
          #?d => ->(g){ g.await_clear&.call},
          #?e => ->(g){ g.board.to_end},
          #?h => ->(g){ g.board.move(x:n*-1)},
          #?i => ->(g){ g.mode = :I },
          #?j => ->(g){ g.board.move(y:1) },
          #?k => ->(g){ g.board.move(y:-1) },
          #?l => ->(g){ g.board.move(x:n)},
          #?r => ->(g){ g.await_replace&.call}
          #?w => ->(g){ g.board.next_clue(n:n)},
        #}
      end
      def self.commands(n:)
        {
          N: {
            ?b => ->(g){ g.board.prev_clue(n:n)},
            ?c => ->(g){ g.await_clear&.call;self.mode=:I},
            ?d => ->(g){ g.await_clear&.call},
            ?e => ->(g){ g.board.to_end},
            ?h => ->(g){ g.board.move(x:n*-1)},
            ?i => ->(g){ g.mode = :I },
            ?j => ->(g){ g.board.move(y:1) },
            ?k => ->(g){ g.board.move(y:-1) },
            ?l => ->(g){ g.board.move(x:n)},
            ?r => ->(g){ g.await_replace&.call},
            ?w => ->(g){ g.board.next_clue(n:n)}
          }
        }
      end
      def self.await_int(n:)

      end
    end
  end
end
