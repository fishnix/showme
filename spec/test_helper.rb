# test_helper.rb
ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'rack/test'

begin
  require_relative '../app'
rescue NameError 
  require File.expand_path('../app', __FILE__)
end