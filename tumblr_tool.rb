# See README.md for details, license and copyright

require 'rubygems'
require 'tumblr'
require 'yaml'
require 'socket'
require 'timeout'

class TumblrTool
  attr_reader :cfg, :client

  def initialize
    @cfg     = YAML::load_file("#{File.dirname(__FILE__)}/config.yml")
    @client  = Tumblr::Client.load(cfg[:hostname], cfg[:credentials])

    @backoff = 10 # small backoff time for transient network errors
    @sleep   = 6 * 60 * 60 # large backoff time for API limit exceeded
    @lives   = 3 # number of small backoffs before failure

    expand_cfg!
  end

  def with_retry
    begin
      yield
    rescue SocketError, TimeoutError => e
      @lives -= 1
      puts "FAIL: Network error, sleeping #{@backoff}s, #{@lives} attempts remaining #{e}"
      if @lives == 0
        raise RuntimeError, "too many errors"
      end
      sleep @backoff
      retry
    rescue RuntimeError => e
      if e.to_s.match(/upload limit/)
        puts "FAIL: Tumblr upload limit reached, sleeping #{@sleep}s"
        sleep @sleep
        retry
      else
        raise RuntimeError, e
      end
    end
  end

  def tumblr_error(response)
    parsed_response = response.parse
    parsed_response["response"].empty? ? response.parse["meta"]["msg"] : parsed_response["response"]["errors"]
  end

  private

  def expand_tilde(path)
    path.gsub(/~/, ENV['HOME'])
  end

  # this monkeying is allow tildes in config files, so i don't need to change
  # them between local (OS X) and remote (FreeBSD) instances of this
  # there's likely some kick-ass way to do this, it escapes me just now
  def expand_cfg!
    @cfg.each do |k,v|
      @cfg[k] = expand_tilde(@cfg[k]) if @cfg[k].respond_to?('gsub')
    end
  end

end
    


