module Cliptic
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
          "^S save | ^R reveal | ^E reset | ^G check"
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
          valid_input? ? raw : (raise Cliptic::Errors::Invalid_Date.new(data[:date]))
        end
        def valid_input?
          JSON.parse(raw, symbolize_names:true)
            .dig(:cells, 0, :meta, :data).length > 0
        end
        def raw
          @raw || Curl.get(URL, data) do |curl|
            curl.ssl_verify_peer = false
          end.body
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
          :coords
        attr_accessor :done, :index, :next, :prev, :cells
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
          def ctrls
            super.merge({
              ?q => ->{back; game.unpause}
            })
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
          def ctrls
            super.merge({
              ?q => ->{back; Screen.clear}
            })
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
        attr_reader :puzzle, :grid, :box, :cursor, :clue, :dir, :state
        def initialize(date:Date.today)#, state:)
          @puzzle = Puzzle::Puzzle.new(date:date)
          @grid   = Grid.new(puzzle:puzzle)
          @box    = Cluebox.new(grid:grid)
          @cursor = Cursor.new(grid:grid)
          #@state  = state
        end
        def setup(state:nil)
          grid.draw
          load_state(state:state)
          set_clue(clue:puzzle.first_clue, mv:true) if !@clue
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
          grid.cells.flatten.each{|cell| cell.clear}
          puzzle.clues.each{|clue| clue.done = false}
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
          puzzle.get_clue_by_index(i:i, dir:dir) || clue
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
          pos[:x] += grid.sq[:x] while pos[:x] < 0
          pos[:y] += grid.sq[:y] while pos[:y] < 0
          pos[:x] -= grid.sq[:x] while pos[:x] >= 
            grid.sq[:x]
          pos[:y] -= grid.sq[:y] while pos[:y] >= 
            grid.sq[:y]
        end
      end
      class Game
        include Database, Windows, Menus
        attr_reader :state, :board, :top_b, :timer, 
          :bot_b, :ctrls , :date
        attr_accessor :mode, :continue, :unsaved
        def initialize(date:Date.today)
          @date  = date
          init_windows
          @timer = Timer.new(time:state.time, bar:top_b, 
                             callback:->{board.update})
          @ctrls = Controller.new(game:self)
          @unsaved  = false
          @continue = true
          draw
        end
        def play
          if state.done
            show_completed_menu
          else
            add_to_recents
            game_and_timer_threads.map(&:join)
          end
        end
        def redraw
          save
          Screen.clear
          init_windows
          draw
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
        def init_windows
          @state = State.new(date:date)
          @board = Board.new(date:date)
          @top_b = Top_Bar.new(date:date)
          @bot_b = Bottom_Bar.new
        end
        def draw
          [top_b, bot_b].each(&:draw)
          self.mode = :N
          board.setup(state:state)
        end
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
          elsif is_arrow_key?(char)
            arrow(char)
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
        def is_arrow_key?(char)
          (258..261).cover?(char)
        end
        def arrow(char)
          mv = case char
          when Curses::KEY_UP    then {y:-1}
          when Curses::KEY_DOWN  then {y:1}
          when Curses::KEY_LEFT  then {x:-1}
          when Curses::KEY_RIGHT then {x:1}
          end
          ->{game.board.move(**mv)}
        end
        def controls(n=1)
          {
            G:{
              3  => ->{game.exit},
              5  => ->{game.reset_menu.choose_opt},
              7  => ->{game.board.puzzle.check_all},
              9  => ->{game.board.swap_direction},
              12 => ->{game.redraw},
              16 => ->{game.pause},
              18 => ->{game.reveal},
              19 => ->{game.save}
            },
            N:{
              ?j => ->{game.board.move(y:n)},
              ?k => ->{game.board.move(y:n*-1)},
              ?h => ->{game.board.move(x:n*-1)},
              ?l => ->{game.board.move(x:n)},
              ?i => ->{game.mode = :I},
              ?I => ->{game.board.to_start; game.mode=:I},
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
end
