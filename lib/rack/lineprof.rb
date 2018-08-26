require 'rblineprof'
require 'logger'
require 'term/ansicolor'
require 'pp'
require 'thread'

class AggregateProfile
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
    result = ''
    @aggregation.keys.each do |file|
      result += "========= #{file} ========="
      File.readlines(file).each_with_index do |line, num|
        wall, cpu, calls, _allocations = @aggregation[file][num + 1]

        result += if wall > 0 || cpu > 0 || calls > 0
                    sprintf("% 5.1fms + % 6.1fms (% 4d) | %s", cpu / 1000.0, (wall - cpu) / 1000.0, calls, line)
                  else
                    sprintf("                          | %s", line)
                  end
      end
      result += "\n"
    end
    result
  end
end

$queue = Queue.new
at_exit do
  puts 'finished!!!!!!!!'
  puts $queue.length
  prof = AggregateProfile.new
  while !$queue.empty?
    prof.add $queue.pop
  end
  puts prof.format
  STDOUT.flush
end

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
      $queue.push profile

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

