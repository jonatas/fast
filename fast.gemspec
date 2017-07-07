# coding: utf-8


Gem::Specification.new do |spec|
  spec.name          = "ffast"
  spec.version       = '0.0.1'
  spec.authors       = ["Jônatas Davi Paganini"]
  spec.email         = ["jonatas.paganini@toptal.com"]

  spec.summary       = %q{FAST: Find by AST.}
  spec.description   = %q{Allow you to search for code using node pattern syntax.}
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = ['fast']
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "parser", "~> 2.4.0.0"
  spec.add_development_dependency 'coderay', '~> 1.1.1'
  spec.add_development_dependency "pry"
end
