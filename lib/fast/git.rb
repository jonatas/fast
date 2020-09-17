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

    # @return [String] with last commit SHA
    def sha
      last_commit.sha
    end

    # @return [String] with remote URL
    def remote_url
      git.remote.url
    end

    # Given #remote_url is "git@github.com:namespace/project.git"
    # @return [String] "https://github.com/namespace/project"
    def project_url
      return remote_url if remote_url.start_with?("https")
      remote_url
        .gsub("git@","https://")
        .gsub(/:(\w)/,"/\\1")
        .gsub(/\.git$/,'')
    end

    def file
      buffer_name.gsub(Dir.pwd + '/', '')
    end



    # @return
    def line_range
      lines.map { |l| "L#{l}" }.join('-')
    end
    # @return [Array] with lines range
    def lines
      exp = loc.expression
      first_line = exp.first_line
      last_line = exp.last_line
      [first_line, last_line].uniq
    end

    # @return [Integer] lines of code from current block
    def lines_of_code
      lines.last - lines.first + 1
    end

    # @return [String] a markdown link with #md_link_description and #github_link
    def md_link(text = md_link_description)
      "[#{text}](#{github_link})"
    end

    # @return [String] with the source cutting arguments from method calls to be
    # able to create a markdown link without parens.
    def md_link_description
      source[/([^\r\(]+)\(/, 1] || source
    end

    # @return [String] with formmatted Github link
    def github_link
      "#{project_url}/blob/master/#{buffer_name}##{line_range}"
    end

    # @return [String] with permanent link to the actual commit
    def permalink
      "#{project_url}/blob/#{sha}/#{buffer_name}##{line_range}"
    end
  end
end
