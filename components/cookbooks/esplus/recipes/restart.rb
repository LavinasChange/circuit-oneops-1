#
# Cookbook Name:: changeme
# Recipe:: restart
#
# Elasticsearch Restart
Chef::Log.info("Elasticsearch restarting...")
bash 'Starting Elasticsearch' do
  code <<-EOH
      sudo service elasticsearch restart
  EOH
end
