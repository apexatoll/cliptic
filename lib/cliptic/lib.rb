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
  module Errors
    class Invalid_Date < StandardError
      attr_reader :date
      def initialize(date)
        @date = date
      end
      def message
        <<~msg
        Invalid date passed #{date}
        Earliest date #{Date.today<<9}
        msg
      end
    end
  end
end
