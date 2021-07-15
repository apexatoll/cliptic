module Cliptic
  module Config
    Dir_Path  = "#{Dir.home}/.config/cliptic"
    File_Path = "#{Dir_Path}/cliptic.rc"
    class Default
      def self.set
        $colors = colors
        $config = make_bool(config)
      end
      private
      def self.colors
        {
          box:8, grid:8, bar:16, logo_grid:8, 
          logo_text:3, title:6, stats:6, active_num:3, 
          num:8, block:8, I:15, N:12, correct:2, 
          incorrect:1, meta:3, cluebox:8, 
          menu_active:15, menu_inactive:0
        }
      end
      def self.config
        {
          auto_advance:1, auto_mark:1, auto_save:1
        }
      end
      def self.make_bool(hash)
        hash.each{|k, v| hash[k] = v == 1 }
      end
    end
    class Custom < Default 
      def self.set
        cfg_file_exists? ? read_cfg : gen_cfg_menu.choose_opt
      end
      private
      def self.read_cfg
        Reader.new.tap do |file|
          key_map.each do |dest, key|
            dest.merge!(file.read(**key))
          end
        end
        make_bool($config)
      end
      def self.key_map
        {
          $colors => {key:"hi"},
          $config => {key:"set"}
        }
      end
      def self.cfg_file_exists?
        File.exist?(File_Path)
      end
      def self.gen_cfg_menu
        Cliptic::Interface::Yes_No_Menu.new(
          yes:->{Generator.new.write},
          title:"Generate config file?"
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
