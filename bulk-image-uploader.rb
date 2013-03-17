#!/usr/bin/env ruby
# encoding: UTF-8

# See README.md for details, license and copyright

$:.push(File.dirname(__FILE__))

require 'rubygems'
require 'tumblr'
require 'time'
require 'yaml'
require 'erb'
require 'tumblr_tool'

class Tumblr::Post::Photo
  # load_data_from_file lets us add the binary image data after
  # we've created the Post from the supplied YAML
  # we can't inline the image as pure binary (TODO: check !binary)
  def load_data_from_file(path)
    @data = File.read(path)
  end
end

src = ARGV.shift
if src.nil? || !File.directory?(src)
  raise ArgumentError, "usage: bulk-image-uploader.rb directory"
end
system("mkdir -p #{src}/.done")

erb = ERB.new(DATA.read)
tt  = TumblrTool.new

# some iPhoto tags we don't want to become Tumblr tags
# some iPhoto tags we want to rename in flight
# load a hash from config of the form
# { :drop => [ tag1, tag2], :map => [ { :from => 'oldtag', :to => 'newtag} ] }
fixups = tt.cfg[:fixups] || { :drop => [], :map => [] }

last_date = Time.now.strftime("%Y:%m:%d %H:%M:%S")

Dir.entries(src).sort.each do |file|
  next unless file.match(/\.jpg/)

  path = "#{src}/#{file}"

  # load caption from IPTC
  caption = %x[ iptc -p Caption #{path} ].chomp.force_encoding('UTF-8')
  if caption.nil?
    caption = ""
  end
  caption.gsub!(/"/, '\"') # escape quotes, since we quote the whole caption
  caption.gsub!(/¡/, '&iexcl;') 
  caption.gsub!(/¿/, '&iquest;') 
  caption.gsub!(/^\n/, "\n\n") # something swallows multiple \n, add them back

  # load tags from IPTC
  # FIXME: map commas in keywords to something else?
  tags = %x[ iptc -p Keywords:all #{path} ].force_encoding('UTF-8').split("\n").map { |t| t.downcase }

  # tweak tags
  fixups[:drop].each do |drop|
    if tags.include?(drop)
      puts "T dropping tag '#{drop}' from #{file}"
      tags -= [ drop ]
    end
  end
  fixups[:map].each do |map|
    from, to = map[:from], map[:to]
    if tags.include?(from)
      puts "T mapping tag '#{from}' to '#{to}'"
      tags -= [ from ]
      unless tags.include?(to)
        tags += [ to ]
      end
    end
  end

  # load date from EXIF
  # no timezone present, we assume TZ(camera) == TZ(localhost)
  date = %x[ exif -t 0x9003 -m #{path} ].chomp
  if $?.success?
    last_date = date
  else
    # panoramas and other weirdies don't have a creation date, only iPhoto's date
    # which just reflects import or edit. use the date of the last photo (or now if
    # this is the first photo)
    puts "! #{file} has no original date, using last known date of #{last_date}"
    date = last_date
  end

  # munge date into a format Tumblr likes, and create YYYY-MM and YYYY tags from it
  md = date.match(%r{^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})})
  if md.nil?
    raise RuntimeError, "couldn't parse #{date}"
  end
  stamp = Time.local($1,$2,$3,$4,$5,$6)
  tags += [ "#{stamp.year}" , "#{stamp.year}-#{sprintf("%02d",stamp.month)}" ]
  
  # add tags from ${TAGS} if present
  if ENV['TAGS']
    tags << ENV['TAGS'].split(',')
  end

  tags.uniq!

  puts "> #{file} (#{date}) #{tags.join(',')} >#{caption}< (#{caption.encoding})"

  begin
    post = Tumblr::Post.load(erb.result(binding))
    puts post.serialize
    post.load_data_from_file(path)
  rescue ArgumentError => e
    puts "! #{file} exploded >#{caption}< #{e}"
  end

  unless ENV['DRY_RUN']
    tt.with_retry do
      print "* #{file} "
      post.publish!
      response = post.post(tt.client).perform
      if response.success?
        print "done"
        system("mv #{src}/#{file} #{src}/.done")
        attempt = false
      else
        raise RuntimeError, tt.tumblr_error(response)
      end
    end
  end

  puts "."

end


__END__

---
type: photo
state: published
tags: <%= tags.join(',') %>
date: <%= stamp.strftime("%b %d, %Y %H:%M %z") %>
caption: "<%= caption %>"
format: markdown
source: nil
---
