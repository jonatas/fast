$: << File.expand_path('../../lib', __FILE__)
require 'fast'

# It's a simple script that you can try to replace
# `create` by `build_stubbed` and it moves the file if
# successfully passed the specs
#
# $ ruby experimental_replacement.rb spec/*/*_spec.rb
def experimental_spec(file, name)
  parts = file.split('/')
  dir = parts[0..-2]
  filename = "experiment_#{name}_#{parts[-1]}"
  File.join(*dir, filename)
end

def experiment(file, name, search, replacement)
  ast = Fast.ast_from_file(file)

  results = Fast.search(ast, search)
  unless results.empty?
    new_content = Fast.replace_file(file, search, replacement)
    new_spec = experimental_spec(file, name)
    return if File.exist?(new_spec)
    File.open(new_spec, 'w+') { |f| f.puts new_content }
    if system("bin/spring rspec --fail-fast #{new_spec}")
      system "mv #{new_spec} #{file}"
      puts "✅ #{file}"
    else
      system "rm #{new_spec}"
      puts "🔴  #{file}"
    end
  end
rescue
  # Avoid stop because weird errors like encoding issues
  puts "🔴🔴 🔴   #{file}: #{$!}"
end

ARGV.each do |file|
  [
    #Thread.new { experiment(file, 'build_stubbed', '(send nil create)', ->(node) { replace(node.location.selector, 'build_stubbed') }) },
    experiment(file, 'seed', '(send nil create)', ->(node) { replace(node.location.selector, 'seed') })

  ] #.each(&:join)
end
