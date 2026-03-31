# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fast/version'

Gem::Specification.new do |spec|
  spec.name          = 'ffast'
  spec.version       = Fast::VERSION
  spec.required_ruby_version = '>= 2.6'
  spec.authors       = ['Jônatas Davi Paganini']
  spec.email         = ['jonatasdp@gmail.com']
  spec.homepage      = 'https://jonatas.github.io/fast/'

  spec.summary       = 'FAST: Find by AST.'
  spec.description   = 'Allow you to search for code using node pattern syntax.'
  spec.license       = 'MIT'

  spec.files = %w[
    lib/fast.rb
    lib/fast/cli.rb
    lib/fast/experiment.rb
    lib/fast/git.rb
    lib/fast/mcp_server.rb
    lib/fast/node.rb
    lib/fast/prism_adapter.rb
    lib/fast/rewriter.rb
    lib/fast/scan.rb
    lib/fast/shortcut.rb
    lib/fast/source.rb
    lib/fast/source_rewriter.rb
    lib/fast/sql.rb
    lib/fast/sql/rewriter.rb
    lib/fast/summary.rb
    lib/fast/version.rb
    bin/fast
    bin/fast-mcp
    bin/fast-experiment
    bin/setup
    bin/console
    .agents/fast-pattern-expert/SKILL.md
    LICENSE.txt
    README.md
    Fastfile
  ]

  spec.post_install_message = <<~THANKS

    ==========================================================
    Yay! Thanks for installing

       ___       __  ___
      |__   /\  /__`  |
      |    /~~\ .__/  |

    To interactive learn about the gem in the terminal use:

    fast .intro

    More docs at: https://jonatas.github.io/fast/
    ==========================================================

  THANKS

  spec.bindir        = 'bin'
  spec.executables   = %w[fast fast-experiment fast-mcp]
  spec.require_paths = %w[lib]

  spec.add_dependency 'coderay'
  spec.add_dependency 'parallel'
  spec.add_dependency 'pg_query'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'git'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-livereload'
  spec.add_development_dependency 'guard-rspec'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-performance'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'simplecov'
end
