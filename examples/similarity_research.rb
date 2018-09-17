require 'bundler/setup'
require 'fast'
require 'coderay'
require 'pp'
require 'set'

arguments = ARGV
pattern = arguments.shift || '{ block case send def defs while class if }'

files = Fast.ruby_files_from(*%w(spec lib app gems)) +
  Dir[File.join(Gem.path.first,'**/*.rb')]

total = files.count
pattern = Fast.expression(pattern)

similarities = {}

def similarities.show pattern
  files = self[pattern]
  files.each do |file|
    nodes = Fast.search_file(pattern, file)
    nodes.each do |result|
      Fast.report(result, file: file)
    end
  end
end

def similarities.top
  self.transform_values(&:size)
  .sort_by{|search,results|search.size / results.size}
  .reverse.select{|k,v|v > 10}[0,10]
end

begin
  files.each_with_index do |file, i|
    progress = ((i / total.to_f) * 100.0).round(2)
    print "\r (#{i}/#{total})   #{progress}%     Researching on #{file}"
    begin
      results = Fast.search_file(pattern, file) || []
    rescue
      next
    end
    results.each do |n|
      search = Fast.expression_from(n)
      similarities[search] ||= Set.new
      similarities[search] << file
    end
  end
rescue Interrupt
# require 'pry'; binding.pry
end

puts "mapped #{similarities.size} cases"
similarities.delete_if {|k,v| k.size < 30 || v.size < 5}
puts "Removing the small ones we have #{similarities.size} similarities"

similarities.show similarities.top[0][0]

