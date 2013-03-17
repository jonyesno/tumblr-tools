#!/usr/bin/env ruby

# See README.md for details, license and copyright

$:.push(File.dirname(__FILE__))

require 'rubygems'
require 'tumblr'
require 'yaml'
require 'tumblr_tool'

offset  = ENV['OFFSET'].to_i || 0
chunk   = 20
last_id = 0

tt = TumblrTool.new
system("mkdir -p #{tt.cfg[:snapshotdir]}")

while true do
  tt.with_retry do
    puts "fetching #{chunk} posts at offset #{offset}, last post #{last_id}"
    req = tt.client.posts(:offset => offset, :limit => chunk)
    response = req.perform
    unless response.success?
      raise RuntimeError, tt.tumblr_error(response)
    end

    posts = response.parse["response"]["posts"]
    new_last_id = posts.last['id']

    if last_id == new_last_id
      break
    else
      last_id = new_last_id
      offset += chunk
    end
  
    posts.each do |p|
      post = Tumblr::Post.create(p)
      puts "#{post.id} #{post.date} #{post.type} #{post.tags}"
      yml = "#{tt.cfg[:snapshotdir]}/#{post.id}.yml"
      # next if File.exists?(yml)
      File.open(yml, "w+") { |f| f.puts post.serialize }
    end
  end
end

puts "done"
