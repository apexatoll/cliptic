require 'cgi'
require 'curb'
require 'curses'
require 'date'
require 'fileutils'
require 'json'
require 'sqlite3'
require 'time'

require_relative "cliptic/version"

module Cliptic
  require_relative "cliptic/lib.rb"
  require_relative "cliptic/config.rb"
  require_relative "cliptic/database.rb"
  require_relative "cliptic/windows.rb"
  require_relative "cliptic/interface.rb"
  require_relative "cliptic/menus.rb"
  require_relative "cliptic/main.rb"
  class Wrapper
    def self.run
      Screen.setup
      Config::Setter.new.set
      Menus::Main.new.choose_opt
    end
  end
end
