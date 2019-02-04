#
# Cookbook Name:: changeme
# Recipe:: stop
#
# Elasticsearch Stop
Chef::Log.info("Elasticsearch stopping...")
bash 'Starting Elasticsearch' do
  code <<-EOH
      sudo service elasticsearch stop
  EOH
end
