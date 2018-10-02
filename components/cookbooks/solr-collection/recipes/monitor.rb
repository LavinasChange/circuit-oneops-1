#
# Cookbook Name :: solr-collection
# Recipe :: monitor.rb
#
# The recipe copies the monitor scripts and its related libraries from inductor to all computes.
#


# Copy the check_shardstatus.rb.erb monitor to /opt/nagios/libexec/check_shardstatus.rb location
template "/opt/nagios/libexec/check_shardstatus.rb" do
  source "check_shardstatus.rb.erb"
  owner "app"
  group "app"
  mode "0755"
  variables({
    :port_no => node['port_num']
  })
  action :create
end

