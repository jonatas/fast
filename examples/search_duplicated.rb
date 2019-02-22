require 'fast'

# Search for duplicated methods interpolating the method and collecting previous
# method names. Returns true if the name already exists in the same class level.
# Note that this example will work only in a single file because it does not
# cover any detail on class level.
def duplicated(method_name)
  @methods ||= []
  already_exists = @methods.include?(method_name)
  @methods << method_name
  already_exists
end

puts Fast.search_file( '(def #duplicated)', 'example.rb')

