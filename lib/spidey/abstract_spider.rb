# encoding: utf-8
require 'mechanize'
require 'proxynova'
module Spidey
  class AbstractSpider
    attr_accessor :urls, :handlers, :results, :request_interval, :errors, :proxy_addr, :proxy_port, :agent
    attr_accessor :proxies, :random_proxy, :total_proxies, :current_proxy
    
    DEFAULT_REQUEST_INTERVAL = 3  # seconds
    
    def self.handle(url, handler, default_data = {})
      start_urls << url
      handlers[url] = [handler, default_data]
    end
    
    # Accepts:
    #   request_interval: number of seconds to wait between requests (default: 3)
    def initialize(attrs = {})
      agent
      @urls = []
      @handlers = {}
      @results = []
      @proxies = []
      @current_proxy = 0
      self.class.start_urls.each { |url| handle url, *self.class.handlers[url] }
      @request_interval = attrs[:request_interval] || DEFAULT_REQUEST_INTERVAL
      @proxy_port = attrs[:proxy_port]
      @proxy_addr = attrs[:proxy_addr]
      @random_proxy = attrs[:random_proxy]
      if @random_proxy == true
        @proxies = Proxynova.get_list
        @total_proxies = @proxies.count
      end
    end
    
    # Make is accessible
    def agent
      @agent = Mechanize.new { |agent|
        agent.user_agent_alias = 'Windows Mozilla'
        agent.open_timeout = 10
        agent.read_timeout = 10
        agent.keep_alive = false
        agent.max_history = 0
      }
    end

    # Cycle true proxy server IPs
    # Could be improved later if we pushed this randomization into Proxynova gem
    def ip_cycle
      if @total_proxies == 0
        @total_proxies = @current_proxy
        @current_proxy = 0
      end
      proxy_server = @proxies[@current_proxy]
      @current_proxy += 1
      @total_proxies -= 1
      proxy_server
    end
  
    # Iterates through URLs queued for handling, including any that are added in the course of crawling. Accepts:
    #   max_urls: maximum number of URLs to crawl before returning (optional)
    def crawl(options = {})
      unless @proxy_addr.nil? || @proxy_port.nil?
        @agent.set_proxy @proxy_addr, @proxy_port
      end

      if @random_proxy == true
        proxy = ip_cycle
        @proxy_addr = proxy[:ip]
        @proxy_port = proxy[:port]
        @agent.set_proxy @proxy_addr, @proxy_port
      end

      @errors = []
      i = 0
      each_url do |url, handler, default_data|
        break if options[:max_urls] && i >= options[:max_urls]
        begin
          page = @agent.get(url)
          Spidey.logger.info "Handling #{url.inspect}"
          send handler, page, default_data
          rescue => ex
          add_error url: url, handler: handler, error: ex
        end
        sleep request_interval if request_interval > 0
        i += 1
      end
    end
  
  protected
  
    # Override this for custom queueing of crawled URLs.
    def handle(url, handler, default_data = {})
        unless @handlers[url]
            @urls << url
            @handlers[url] = [handler, default_data]
        end
    end
    
    # Override this for custom storage or prioritization of crawled URLs.
    # Iterates through URL queue, yielding the URL, handler, and default data.
    def each_url(&block)
        urls.each do |url|
            yield url, handlers[url].first, handlers[url].last
        end
    end
  
    # Override this for custom result storage.
    def record(data)
        results << data
        Spidey.logger.info "Recording #{data.inspect}"
    end
    
    # Override this for custom error-handling.
    def add_error(attrs)
        @errors << attrs
        Spidey.logger.error "Error on #{attrs[:url]}. #{attrs[:error].class}: #{attrs[:error].message}"
    end
    
    def resolve_url(href, page)
        @agent.agent.resolve(href, page).to_s
    end
    
    # Strips ASCII/Unicode whitespace from ends and substitutes ASCII for Unicode internal spaces.
    def clean(str)
        return nil unless str
        str.gsub(/\p{Space}/, ' ').strip.squeeze(' ')
    end
  
  private
  
    def self.start_urls
        @start_urls ||= []
    end

    def self.handlers
        @handlers ||= {}
    end

  end
end