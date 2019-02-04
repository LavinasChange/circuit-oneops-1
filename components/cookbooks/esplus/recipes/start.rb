#
# Cookbook Name:: changeme
# Recipe:: start
#
# Elasticsearch Start
Chef::Log.info("Elasticsearch starting...")
bash 'Starting Elasticsearch' do
  code <<-EOH
      sudo service elasticsearch start
  EOH
end
