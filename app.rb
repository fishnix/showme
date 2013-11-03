require 'sinatra'
require 'f5-icontrol'
require 'date'
require 'sinatra/config_file'
require 'sinatra/multi_route'
require 'dalli'
require 'rack-cache'
require 'pathname'

use Rack::MethodOverride

# Switch to using Memcachier since Memcached service is going away
if memcachier_servers = ENV['MEMCACHIER_SERVERS']
  cache = Dalli::Client.new memcachier_servers.split(','), {
    username: ENV['MEMCACHIER_USERNAME'],
    password: ENV['MEMCACHIER_PASSWORD']
  }

  use Rack::Cache, verbose: true, metastore: cache, entitystore: cache
end

config_file 'config.yml'
set :protection, :except => :frame_options

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

get "/" do
 redirect '/virtuals'
end

get "/pools" do
  cache_control :public, max_age: 1800  # 30 mins.

  @heading = "Pools"
  @pools = pools

  erb :pools
end

get "/pool/:pool_name" do
  cache_control :public, max_age: 1800  # 30 mins.

  @heading = params[:pool_name]
  @pool = pool(params[:pool_name])

  erb :pool
end

get "/virtuals" do
  cache_control :public, max_age: 1800  # 30 mins.

  @heading = "Virtuals"
  @virtuals = virtuals

  erb :virtuals
end


get '/rules', '/rule/:rule_name' do 
  cache_control :public, max_age: 1800  # 30 mins.

  @heading = params[:rule_name] ? params[:rule_name] : "iRules"
  @rules = params[:rule_name] ? rules([params[:rule_name]]) : rules

  erb :rules
end

get "/datagroups/:type" do
  cache_control :public, max_age: 1800  # 30 mins.

  @heading = "Data Groups"
  @type = params[:type]
  @datagroups = datagroups(params[:type])

  erb :datagroups
end

error do
  'Sorry there was a nasty error - ' + env['sinatra.error'].name
end

not_found do
  'This is nowhere to be found.'
end


private

def pools
  bigip = get_bigip_ifaces('LocalLB.Pool')

  pools = bigip['LocalLB.Pool'].get_list.sort
  pool_active_members = bigip['LocalLB.Pool'].get_active_member_count(pools)

  Hash[pools.zip pool_active_members]
end

def pool(pool_name)
  bigip = get_bigip_ifaces('LocalLB.Pool')
  members = bigip['LocalLB.Pool'].get_member_v2([pool_name])
  statuses = bigip['LocalLB.Pool'].get_member_monitor_status([pool_name], members)

  members[0].each do |m|
    puts m.address
  end

  statuses.each do |s|
    puts s
  end

  mem = Hash[members[0].zip statuses]
  mem.each do |m,s|
    #mem["#{m.address}:#{m.port}"] = 
    puts "#{m.address}:#{m.port} = #{s}"
  end
end


def virtuals
  bigip = get_bigip_ifaces('LocalLB.VirtualServer')

  virtuals      = bigip['LocalLB.VirtualServer'].get_list.sort
  dests         = bigip['LocalLB.VirtualServer'].get_destination_v2(virtuals)
  enabled       = bigip['LocalLB.VirtualServer'].get_enabled_state(virtuals)
  status        = bigip['LocalLB.VirtualServer'].get_object_status(virtuals)
  pools         = bigip['LocalLB.VirtualServer'].get_default_pool_name(virtuals)
  persists      = bigip['LocalLB.VirtualServer'].get_persistence_profile(virtuals)
  fbpersists    = bigip['LocalLB.VirtualServer'].get_fallback_persistence_profile(virtuals)
  rules         = bigip['LocalLB.VirtualServer'].get_rule(virtuals)
  profile       = bigip['LocalLB.VirtualServer'].get_profile(virtuals)
    
  arr = Array.new
  virtuals.zip(enabled, status, dests, pools, persists, fbpersists, rules, profile) do |a,b,c,d,e,f,g,h,i|
    virt = Hash.new
    virt[:name]        = a
    virt[:enabled]     = b
    virt[:status]      = c
    virt[:destination] = d
    virt[:pool]        = e
    virt[:persist]     = f
    virt[:fbpersist]   = g
    virt[:rules]       = h
    virt[:profile]     = i
    arr << virt
  end
  
  # Return array of virtuals
  arr
end

def rules(rules = nil)
  bigip = get_bigip_ifaces('LocalLB.Rule')

  rules ||= bigip['LocalLB.Rule'].get_list.sort

  bigip['LocalLB.Rule'].query_rule(rules)
end

def datagroups(type)
  bigip = get_bigip_ifaces('LocalLB.Class')

  case type
    when "address"
      datagroups = bigip['LocalLB.Class'].get_address_class_list.sort
      datagroups = bigip['LocalLB.Class'].get_address_class(datagroups)
      Hash[datagroups.zip Array.new(datagroups.length, nil)]
    when "string"
      datagroups = bigip['LocalLB.Class'].get_string_class_list.sort
      # Get list of [{:name => 'name', :members => [foo,bar,baz]}, ... ]
      datagroups = bigip['LocalLB.Class'].get_string_class(datagroups)
      values = bigip['LocalLB.Class'].get_string_class_member_data_value(datagroups)
      Hash[datagroups.zip values]
    when "value"
      datagroups = bigip['LocalLB.Class'].get_value_class_list.sort
      bigip['LocalLB.Class'].get_value_class(datagroups)
  end  
end

def get_bigip_ifaces(ic_module)

  modules = ['Management.Partition']
  modules << ic_module

  bigip = F5::IControl.new( settings.mgmt_host, \
                      settings.mgmt_user, \
                      settings.mgmt_pass, \
                      modules).get_interfaces

  partitions = bigip['Management.Partition'].set_active_partition('/Common')

  bigip
end
