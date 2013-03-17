#!/usr/bin/env ruby

# See README.md for details, license and copyright

$:.push(File.dirname(__FILE__))

require 'rubygems'
require 'tumblr'
require 'yaml'
require 'tumblr_tool'

tt = TumblrTool.new

Dir.entries(tt.cfg[:snapshotdir]).each do |f|
  next unless f.match(/\d+\.yml/)
  
  old = "#{tt.cfg[:snapshotdir]}/#{f}"
  new = "#{tt.cfg[:workdir]}/#{f}"

  next unless File.exists?(new)

  system("diff -q #{old} #{new} > /dev/null")
  unless $?.success?
    puts "#{f} has changed, uploading from #{tt.cfg[:workdir]}"

    if ENV['DRY_RUN']
      system("diff -u #{old} #{new}")
    else
      tt.with_retry do
        post = Tumblr::Post.load_from_path("#{tt.cfg[:workdir]}/#{f}")
        response = post.edit(tt.client).perform
        unless response.success?
          raise RuntimeError, tt.tumblr_error(response)
        end
      end
    end

  end

end

