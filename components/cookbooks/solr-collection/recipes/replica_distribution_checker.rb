require "/opt/solr-recipes/replica-distributor/solr_apis.rb"
require 'json'

include_recipe 'solr-collection::default'

cloud_provider = CloudProvider.new(node)
clouds_payload = cloud_provider.get_clouds_payload(node)
computes_payload = CloudProvider.get_computes_payload(node)
port_num = node['port_num']

# Copy the replica_distribution_checker.rb.erb monitor to /opt/nagios/libexec/replica_distribution_checker.rb location
template "/opt/nagios/libexec/replica_distribution_checker.rb" do
  source "replica_distribution_checker.rb.erb"
  owner "app"
  group "app"
  mode "0755"
  variables({
                :clouds_payload => clouds_payload.to_json,
                :computes_payload => computes_payload.to_json,
                :port_num => port_num
            })
  action :create
end