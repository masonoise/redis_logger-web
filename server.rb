#
# This code originally borrowed from the resque-web project and modified
# to handle the redis-logger functionality. Everything that's nice is from
# resque-web and the rest is new, I'm sure.
#

require 'rubygems'
require 'sinatra'
require 'erb'
require 'redis'
require 'redis_logger'

module RedisLoggerWeb
  class Server < Sinatra::Base

    dir = File.dirname(File.expand_path(__FILE__))

    # Reload updated code if running in development
    configure :development do
      use Rack::Reloader
      set :logging, true
    end
    
    set :views,  "#{dir}/server/views"
    set :public, "#{dir}/server/public"
    set :static, true

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def current_section
        url request.path_info.sub('/','').split('/')[0].downcase
      end

      def current_page
        url request.path_info.sub('/','')
      end

      def url(*path_parts)
        [ path_prefix, path_parts ].join("/").squeeze('/')
      end
      alias_method :u, :url

      def path_prefix
        request.env['SCRIPT_NAME']
      end

      def class_if_current(path = '')
        'class="current"' if current_page[0, path.size] == path
      end

      def tab(name)
        dname = name.to_s.downcase
        path = url(dname)
        "<li #{class_if_current(path)}><a href='#{path}'>#{name}</a></li>"
      end

      def tabs
        RedisLoggerWeb::Server.tabs
      end

      def redis_get_size(key)
        case RedisLogger.redis.type(key)
        when 'none'
          []
        when 'list'
          @redis.llen(key)
        when 'set'
          @redis.scard(key)
        when 'string'
          @redis.get(key).length
        when 'zset'
          @redis.zcard(key)
        end
      end

      def redis_get_value_as_array(key, start=0)
        case RedisLogger.redis.type(key)
        when 'none'
          []
        when 'list'
          @redis.lrange(key, start, start + 20)
        when 'set'
          @redis.smembers(key)[start..(start + 20)]
        when 'string'
          [@redis.get(key)]
        when 'zset'
          @redis.zrange(key, start, start + 20)
        end
      end

      def show_args(args)
        Array(args).map { |a| a.inspect }.join("\n")
      end

      def partial?
        @partial
      end

      def partial(template, local_vars = {})
        @partial = true
        erb(template.to_sym, {:layout => false}, local_vars)
      ensure
        @partial = false
      end

    end # of helpers


    # Handle nested parameters so the groups[] checkboxes work.
    before do
      new_params = {}
      params.each_pair do |full_key, value|
        this_param = new_params
        split_keys = full_key.split(/\]\[|\]|\[/)
        split_keys.each_index do |index|
          break if split_keys.length == index + 1
          this_param[split_keys[index]] ||= {}
          this_param = this_param[split_keys[index]]
       end
       this_param[split_keys.last] = value
      end
      request.params.replace new_params
    end
    

    def show(page, layout = true)
      begin
        erb page.to_sym, {:layout => layout }, :locals => { :redis => RedisLogger.redis }
      rescue Errno::ECONNREFUSED
        erb :error, {:layout => false}, :error => "Can't connect to Redis! (#{RedisLogger.redis.server})"
      end
    end

    # to make things easier on ourselves
    get "/?" do
      redirect url(:overview)
    end

    %w( overview groups intersect ).each do |page|
      get "/#{page}" do
        show page
      end

      get "/#{page}/:id" do
        show page
      end
    end

    # TODO: Add clear capability
    post "/clear/:id" do
      #RedisLogger::Group.clear
      redirect u('groups')
    end
    
    def self.tabs
      @tabs ||= ["Overview", "Groups"]
    end
  end
end
