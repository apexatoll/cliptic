module Cliptic
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
        $colors = Default.colors
        $config = Default.config
      end
      def set
        cfg_file_exists? ? 
          read_cfg : gen_cfg_menu.choose_opt
        $config = make_bool($config)
      end
      private
      def read_cfg
        Reader.new.tap do |file|
          cfg_file_keys.each do |dest, key|
            dest.merge!(file.read(**key))
          end
        end
      end
      def cfg_file_keys
        {
          $colors => {key:"hi"},
          $config => {key:"set"}
        }
      end
      def cfg_file_exists?
        File.exist?(File_Path)
      end
      def make_bool(hash)
        hash.map{|k, v| [k, v == 1]}.to_h
      end
      def gen_cfg_menu
        Cliptic::Interface::Yes_No_Menu.new(
          yes:->{Generator.new.write},
          title:"Generate a config file?"
        )
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
    class Generator
      def write
        FileUtils.mkdir_p(Dir_Path) unless cfg_dir_exists
        File.write(File_Path, make_file)
      end
      private
      def cfg_dir_exists
        Dir.exist?(Dir_Path)
      end
      def file_data
        {
          "Colour Settings" => {
            cmd:"hi", values:Default.colors
          },
          "Interface Settings" => {
            cmd:"set", values:Default.config
          }
        }
      end
      def make_file
        file_data.map do |comment, data|
          ["//#{comment}"] + data[:values].map{|k, v| "#{data[:cmd]} #{k} #{v}"} + ["\n"]
        end.join("\n")
      end
    end
  end
end
