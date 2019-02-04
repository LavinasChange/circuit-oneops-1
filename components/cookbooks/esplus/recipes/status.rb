#
# Cookbook Name:: changeme
# Recipe:: status
#
# Elasticsearch Status
Chef::Log.info("Elasticsearch status...")
bash 'Starting Elasticsearch' do
  code <<-EOH
      sudo service elasticsearch status
  EOH
end