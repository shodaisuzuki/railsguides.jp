#require 'rack/jekyll'
require 'bundler/setup'
Bundler.require(:default)

run Rack::Jekyll.new
