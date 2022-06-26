# Solar Flux API
# ==============
# This API (/solar-flux.json) returns the latest solar flux data points from NOAA, updated approx once per minute.
# Data source: https://services.swpc.noaa.gov/json/goes/primary/xrays-6-hour.json
#
# This API is provided for free, and without warranties.
# Notes: The NOAA data source is usually 3-5min behind.
# Source: https://github.com/chendo/solar-flux-api
# License: MIT

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'sinatra'
  gem 'puma'
  gem 'excon'
end

set :app_file, $0

class SolarFlux
  class << self
    def init
      @mutex = Mutex.new
    end

    def with_lock(&block)
      @mutex.synchronize(&block)
    end
      
    def get_data
      resp = Excon.get("https://services.swpc.noaa.gov/json/goes/primary/xrays-6-hour.json", expects: [200], retry_limit: 3, retry_interval: 3)

      data = JSON.parse(resp.body)

      by_energy = data.group_by { |point| point.fetch('energy') }

      last_points = by_energy.map do |energy, points|
        [energy, points.sort_by { |point| Time.parse(point.fetch('time_tag')).to_i }.last]
      end

      Hash[last_points]
    end

    def api_response
      data = with_lock { get_data }
      response = {
        timestamp: data.values.first.fetch('time_tag'),
        flux_short: data.fetch('0.05-0.4nm').fetch('flux'),
        flux_long: data.fetch('0.1-0.8nm').fetch('flux'),
        raw: data
      }
    end

    def cached_api_response
      if @last_fetch && @last_fetch > Time.now - 60
        return @cached_response
      end

      @last_fetch = Time.now
      @cached_response = api_response
    end
  end
end

SolarFlux.init

README = File.
          readlines($0).
          chunk { |line| line[0] == "#" }.
          first.last.map { |line| line.sub(/\A# ?/, '') }.join

get '/' do
  README
end

get '/solar-flux.json' do
  JSON.dump(SolarFlux.cached_api_response)
end