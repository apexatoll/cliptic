module Cliptic
  module Config
    Dir_Path  = "#{Dir.home}/.config/cliptic"
    File_Path = "#{Dir_Path}/cliptic.rc"
    class Default
      def self.colors
        {
          grid:8, I:15, N:12
          
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
    class Set
      attr_accessor :colors, :config
      def initialize
        @colors = Default.colors
        @config = Default.config
      end
      def set
        read
        $colors = colors
        $config = config
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
        lines.grep(/^\s*#{key}/)
          .map{|l| l.gsub(/^\s*#{key}\s+/, "")
          .split(/\s+/)}
          .map{|k, v| [k.to_sym, v.to_i]}
          .to_h
      end
    end
    class Make
      
    end
  end
end
