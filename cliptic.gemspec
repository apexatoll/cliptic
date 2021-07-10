require_relative "lib/cliptic/version"

Gem::Specification.new do |spec|
  spec.name = "cliptic"
  spec.version = Cliptic::VERSION
  spec.authors = ["Christian Welham"]
  spec.email = ["welhamm@gmail.com"]
  spec.summary = "Terminal-based cryptic crossword player"
  spec.description = "A terminal user interface to fetch and play cryptic crosswords"
  spec.homepage = "http://test.com"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")
  spec.metadata["allowed_push_host"] = "http://mygemserver.com"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "http://github.com"
  spec.metadata["changelog_uri"] = "http://github.com"
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir = "bin"
  spec.executables << "cliptic"
  spec.require_paths = ["lib"]
  #spec.add_dependency("curb")
  #spec.add_dependency("curses")
end
