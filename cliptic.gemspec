require_relative "lib/cliptic/version"

Gem::Specification.new do |spec|
  spec.name = "cliptic"
  spec.version = Cliptic::VERSION
  spec.authors = ["Christian Welham"]
  spec.email = ["welhamm@gmail.com"]
  spec.summary = "Terminal-based cryptic crossword player"
  spec.description = "A terminal user interface to fetch and play cryptic crosswords"
  spec.homepage = "https://github.com/apexatoll/cliptic"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/apexatoll/cliptic"
  spec.metadata["changelog_uri"] = "https://github.com/apexatoll/cliptic/CHANGELOG.md"
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir = "bin"
  spec.executables << "cliptic"
  spec.require_paths = ["lib"]
  spec.add_dependency("curses", "~> 1.4.0")
  spec.add_dependency("curb", "~> 0.9.11")
  spec.add_dependency("sqlite3", "~> 1.4.2")
end
