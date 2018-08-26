require 'rblineprof'
require 'logger'
require 'term/ansicolor'
require 'pp'
require 'thread'
require 'json'

class Prof
  def initialize
    @aggregation = {}
  end

  def add profile
    profile.keys.each do |file|
      puts file
      if @aggregation[file]
        @aggregation[file].size.times do |line|
          (0..3).each do |i|
            @aggregation[file][line][i] += profile[file][line][i]
          end
        end
      else
        @aggregation[file] = profile[file].dup
      end
    end
  end

  def format
    sources = @aggregation.map do |filename, samples|
      Source.new filename, samples, ::Logger.new(STDOUT)
    end

    sources.map(&:format).compact.join "\n"
  end
end

at_exit do
  prof = Prof.new
  File.open(PROFILE_LOG_FILE, 'r') do |f|
    f.readlines.each do |log_line|
      log = JSON.parse log_line
      prof.add({ log['filename'] => log['samples'] })
    end
  end
  puts prof.format
  STDOUT.flush
end

PROFILE_LOG_FILE='./profile.log'

module Rack
  class Lineprof

    autoload :Sample, 'rack/lineprof/sample'
    autoload :Source, 'rack/lineprof/source'

    CONTEXT  = 0
    NOMINAL  = 1
    WARNING  = 2
    CRITICAL = 3

    attr_reader :app, :options

    def initialize app, options = {}
      @app, @options = app, options
    end

    def call env
      request = Rack::Request.new env
      matcher = request.params['lineprof'] || options[:profile]

      return @app.call env unless matcher

      response = nil
      profile = lineprof(%r{#{matcher}}) { response = @app.call env }
      ::File.open(PROFILE_LOG_FILE, 'a') do |f|
        f.flock(::File::LOCK_EX)
        profile.keys.each do |file|
          f.write(
            JSON.dump(
              filename: file,
              samples: profile[file]
            )
          )
          f.write "\n"
        end
      end

      response
    end

    def format_profile profile
      sources = profile.map do |filename, samples|
        Source.new filename, samples, options
      end

      sources.map(&:format).compact.join "\n"
    end

  end
end

