# Cookbook Name:: kafka_console
# Recipe:: pkg_install.rb
#
# Copyright 2015, @WalmartLabs
#
# All rights reserved - Do Not Redistribute

# install kafka binary
payLoad = node.workorder.payLoad[:kafka].select { |cm| cm['ciClassName'].split('.').last == 'Kafka'}.first

Chef::Log.info("payload: #{payLoad.inspect.gsub("\n"," ")}" )

if payLoad.nil?
    Chef::Log.error("kafka_metadata is missing.")
    exit 1
end

Chef::Log.info("ciAttributes content: "+payLoad["ciAttributes"].inspect.gsub("\n"," "))
kafka_version = payLoad["ciAttributes"]["version"]

cloud = node.workorder.cloud.ciName

mirror_svc = node[:workorder][:services][:mirror]
mirror = JSON.parse(mirror_svc[cloud][:ciAttributes][:mirrors]) if !mirror_svc.nil?
base_url = ''

if kafka_version.to_i < 1
    mirror_url_key = "strati_kafka" 
    Chef::Log.info("Getting mirror service for #{mirror_url_key}, cloud: #{cloud}")

    kafka_rpm = "kafka-strati-2.11-#{kafka_version}-noarch.rpm"
	base_url = mirror[mirror_url_key] if !mirror.nil? && mirror.has_key?(mirror_url_key)

	if base_url.empty?
		Chef::Log.error("#{mirror_url_key} mirror is empty for #{cloud}.")
	end

	kafka_download = base_url + "2.11-#{kafka_version}/#{kafka_rpm}"

  execute "remove kafka" do
    user "root"
    exists = <<-EOF
    rpm -qa | grep 'kafka'
    EOF
    command "rpm -e $(rpm -qa '*kafka*')"
    only_if exists, :user => "root"
  end

  # download kafka
  remote_file ::File.join(Chef::Config[:file_cache_path], "#{kafka_rpm}") do
    owner "root"
    mode "0644"
    source kafka_download
    action :create
  end

  # install kafka
  execute 'install kafka' do
    user "root"
    cwd Chef::Config[:file_cache_path]
    command "rpm -i #{kafka_rpm} --force"
  end
else
    mirror_url_key="apache_kafka"
    Chef::Log.info("Getting mirror service for #{mirror_url_key}, cloud: #{cloud}")

    base_url = mirror[mirror_url_key] if !mirror.nil? && mirror.has_key?(mirror_url_key)
 
	if base_url.empty?
		Chef::Log.error("#{mirror_url_key} mirror is empty for #{cloud}.")
	end
   	kafka_download =  base_url + "#{kafka_version}/kafka_2.11-#{kafka_version}.tgz"
  
  `rm -rf /usr/local/kafka/* && mkdir -p /usr/local/kafka`

  remote_file "/usr/local/kafka/kafka_2.11-#{kafka_version}.tgz" do
    owner "root"
    mode "0644"
    source kafka_download
    action :create
  end

  execute 'install kafka' do
    user "root"
    cwd '/usr/local/kafka'
    command "tar -zxf kafka_2.11-#{kafka_version}.tgz -C /usr/local/kafka --strip-components=1"
  end
end

kafka_manager_rpm = node['kafka_console']['console']['filename']

mirror_url_key="kafka_manager"
base_url = mirror[mirror_url_key] if !mirror.nil? && mirror.has_key?(mirror_url_key)
 
if base_url.empty?
	Chef::Log.error("#{mirror_url_key} mirror is empty for #{cloud}.")
end
kafka_manager_download = base_url + "1.3.3.6-1/#{kafka_manager_rpm}"

# remove kafka-manager, if it has been installed
execute "remove kafka-manager" do
  user "root"
  exists = <<-EOF
  rpm -qa | grep 'kafka-manager'
  EOF
  command "rpm -e $(rpm -qa 'kafka-manager*')"
  only_if exists, :user => "root"
end

# download kafka-manager
remote_file ::File.join(Chef::Config[:file_cache_path], "#{kafka_manager_rpm}") do
  owner "root"
  mode "0644"
  source kafka_manager_download
  action :create
end

# install kafka-manager
execute 'install kafka-manager' do
  user "root"
  cwd Chef::Config[:file_cache_path]
  command "rpm -i #{kafka_manager_rpm} --force"
end

# install nginx
execute 'install nginx' do
  user "root"
  cwd Chef::Config[:file_cache_path]
  command "yum install nginx -y"
end
