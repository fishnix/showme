# test_spec.rb
begin 
  require_relative 'test_helper'
rescue NameError
  require File.expand_path('test_helper', __FILE__)
end

include Rack::Test::Methods

def app() Sinatra::Application end

describe "the showme app" do 
  it "should successfully redirect /" do
    get '/'
    last_response.status.must_equal(302)
  end
  
  it "should generate a list of pools" do
    get '/p'
    last_response.status.must_equal(200)
  end
 
  it "should return 404 for non-existent pages" do
    get "/nothere"
    last_response.status.must_equal(404)
  end
end
