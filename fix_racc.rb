content = File.read('fast.gemspec')
content.sub!(/  spec.add_dependency 'parser'/, "  spec.add_dependency 'parser'\n  spec.add_dependency 'racc'")
File.write('fast.gemspec', content)
