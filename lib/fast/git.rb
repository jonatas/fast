# frozen_string_literal: true

# Git plugin for Fast::Node.
# It allows to easily access metadata from current file.
module Fast
  # This is not required by default, so to use it, you should require it first.
  #
  #  @example
  #    require 'fast/git'
  #    Fast.ast_from_file('lib/fast.rb').git_log.first.author.name # => "Jonatas Davi Paganini"
  class Node < Astrolabe::Node
    # @return [Git::Base] from current directory
    def git
      require 'git' unless defined? Git
      Git.open('.')
    end

    # @return [Git::Object::Blob] from current #buffer_name
    def git_blob
      return unless from_file?

      git.gblob(buffer_name)
    end

    # @return [Git::Log] from the current #git_blob
    #  buffer-name
    def git_log
      git_blob.log
    end

    # @return [Git::Object::Commit]
    def last_commit
      git_log.first
    end
  end
end
