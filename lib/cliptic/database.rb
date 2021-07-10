module Cliptic
  module Database
    Dir_Path  = "#{Dir.home}/.config/cliptic/db"
    File_Path = "#{Dir_Path}/cliptic.db"
    class SQL
      attr_reader :db, :table
      def initialize(table:)
        make_db_dir
        @table = table
        @db    = SQLite3::Database.open(File_Path)
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
      def drop
        db.execute("DROP TABLE #{table}")
      end
      private
      def make_db_dir
        FileUtils.mkdir_p(Dir_Path) unless Dir.exist?(Dir_Path)
      end
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
    class Delete
      def self.table(table)
        SQL.new(table:table).drop
      end
      def self.all
        File.delete(File_Path)
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
end
