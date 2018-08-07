#
# Cookbook Name:: mirrormaker
# Recipe:: rpm 
#
# Copyright 2015, WalmartLabs
#
# All rights reserved - Do Not Redistribute
#

kafka_version = node.workorder.rfcCi.ciAttributes.version


if kafka_version.to_i < 1
	kafka_rpm = "kafka-#{kafka_version}.noarch.rpm"

	cloud = node.workorder.cloud.ciName
	mirror_url_key = "lola"
	Chef::Log.info("Getting mirror service for #{mirror_url_key}, cloud: #{cloud}")

	mirror_svc = node[:workorder][:services][:mirror]
	mirror = JSON.parse(mirror_svc[cloud][:ciAttributes][:mirrors]) if !mirror_svc.nil?
	base_url = ''
	# Search for 'lola' mirror
	base_url = mirror[mirror_url_key] if !mirror.nil? && mirror.has_key?(mirror_url_key)

	if base_url.empty?
		Chef::Log.error("#{mirror_url_key} mirror is empty for #{cloud}.")
	end

	kafka_download = base_url + "#{kafka_rpm}"

	Chef::Log.info("kafka_download = #{kafka_download}")

	directory node['mirrormaker'][:rpm_dir] do
	  owner "#{node['mirrormaker'][:user]}"
	  group "#{node['mirrormaker'][:group]}"
	  mode "0755"
	  action :create
	end

	# uninstall kafka rpm
	execute "remove kafka" do
		user "root"
		exists = <<-EOF
		rpm -qa | grep 'kafka'
		EOF
		command "rpm -e $(rpm -qa '*kafka*'); rm -rf /usr/local/kafka/*"
		only_if exists, :user => "root"
	end

	remote_file "#{node['mirrormaker'][:rpm_dir]}/kafka.rpm" do
	  source kafka_download
	  mode  "0755"
	  action :create
	end

	execute "Add kafka" do
		command "rpm -i #{node['mirrormaker'][:rpm_dir]}/kafka.rpm --force"
	end

	# remove bwm-ng
	execute "remove bwm-ng" do
		user "root"
		exists = <<-EOF
		rpm -qa | grep 'bwm-ng'
		EOF
		command "rpm -e $(rpm -qa 'bwm-ng')"
		only_if exists, :user => "root"
	end

	# install bwm-ng
	if ["redhat", "centos", "fedora"].include?(node["platform"])
		yum_package "bwm-ng" do
			action :install
		end
	else
		Chef::Log.error("we currently support redhat, centos, fedora. You are using some OS other than those.")
	end
else
   kafka_download = "https://repository.walmart.com/repository/apache-dist-archive/kafka/#{kafka_version}/kafka_2.11-#{kafka_version}.tgz"
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

