# frozen_string_literal: true

require 'fast/summary'

module Fast
  class Resume < Summary
    def initialize(code_or_ast, file: nil)
      super(code_or_ast, file: file, command_name: '.resume')
    end
  end
end
