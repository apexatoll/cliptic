require 'sqlite3'
module Cliptic
  module Database
    Path = "#{Dir.home}/db/cw.db"
    class Handler
      attr_reader :db, :table
      def initialize(table:)
        @db, @table = SQLite3::Database.open(Path), table
        self
      end
      def make
        db.execute(sql_make)
      end
      def select(cols:"*", where:nil, ord:nil, limit:nil)
        db.execute(sql_select(c:cols, w:where, ord:ord, limit:limit), 
         where&.values&.map(&:to_s))
      end
      def insert(values:)
        db.execute(sql_insert(values:values), values.values)
      end
      def update(values:, where:)
        db.execute(sql_update(values:values, where:where), [values.values],  [where.values] )
      end
      private
      def sql_make
        "CREATE TABLE IF NOT EXISTS #{table}(#{
          cols.map{|col, type| "#{col} #{type}"}.join(", ")
        })"
      end
      def sql_select(c:, w:nil, ord:nil, limit:nil)
        str = "SELECT #{c} FROM #{table}"
        str+= " WHERE #{placeholder(w.keys)}" if w
        str+= " ORDER BY #{ord.keys[0]} #{ord.values[0]}" if ord
        str+= " LIMIT #{limit}" if limit
        return str
      end
      def sql_insert(values:)
        <<~sql
        INSERT INTO #{table}(#{values.keys.join(", ")})
        VALUES (#{
          Array.new(values.length, "?").join(", ")
        })
        sql
      end
      def sql_update(values:, where:)
        <<~sql
        UPDATE #{table}
        SET #{placeholder(values.keys, ", ")}
        WHERE #{placeholder(where.keys)}
        sql
      end
      def placeholder(keys, glue = " AND ")
        keys.map{|k| "#{k} = ?"}.join(glue)
      end
    end
    class State < Handler
      attr_reader :date, :time, :chars, :n_done, 
        :n_tot, :reveals, :done
      def initialize(date:Date.today)
        @date = date
        super(table:"states").make
        @time,@chars,@n_done,@n_tot,@reveals,@done = init
      end
      def cols
        {
          date: :DATE,
          time: :INT,
          chars: :TEXT,
          n_done: :INT,
          n_tot: :INT,
          reveals: :INT,
          done: :INT
        }
      end
      def init
        exists ? 
          [ query[0][1].to_i,
            parse_chars(query[0][2]),
            query[0][3].to_i,
            query[0][4].to_i,
            query[0][5].to_i,
            query[0][6].to_i == 1 ] :
          [ 0, false, nil, nil, 0, false ]
      end
      def exists
        @exists || query.count > 0
      end
      def save(game:)
        build(game:game).tap do |data|
          exists ? 
            update(where:{date:date.to_s}, values:data)
              .tap{@exists = true} :
            insert(values:data)
        end
      end
      private
      def query
        @query || select(where:{date:date})
      end
      def parse_chars(str)
        JSON.parse(str, {symbolize_names:true})
      end
      def build(game:)
        {
          date:    date.to_s,
          time:    game.timer.time.to_i,
          chars:   gen_chars(game),
          n_done:  game.board.puzzle.n_done,
          n_tot:   game.board.puzzle.n_total,
          reveals: game.reveals,
          done:    game.board.puzzle.complete? ? 1 : 0
        }
      end
      def gen_chars(game)
        JSON.generate(game.board.save_state)
      end
    end
    class Scores < Handler
      def initialize
        super(table:"scores").make
      end
      def add(game:)
        insert(values:build(game:game))
      end
      def cols
        {
          date:      :DATE,
          date_done: :DATE,
          time:      :TEXT,
          reveals:   :INT
        }
      end
      def build(game:)
        {
          date:game.date.to_s,
          date_done:Date.today.to_s,
          time:game.timer.time.to_s,
          reveals:game.reveals
        }
      end
      def select
        super(cols:"*", where:{reveals:0}, ord:{time:"ASC"}, limit:10)
      end
    end
    class Recents < Handler
      def initialize
        super(table:"recents").make
      end
      def cols
        {
          date:      :DATE,
          play_date: :DATE,
          play_time: :TIME
        }
      end
      def add(date:)
        insert(values:build(date:date))
      end
      def build(date:)
        {
          date:      date.to_s,
          play_date: Date.today.to_s,
          play_time: Time.now.strftime("%T")
        }
      end
      def select
        super(cols:"*", ord:{play_date:"DESC"}, limit:10)
      end
    end
  end
end


