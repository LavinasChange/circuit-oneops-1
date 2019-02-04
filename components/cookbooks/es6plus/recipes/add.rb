require 'json'
require 'yaml'

[Chef::Recipe, Chef::Resource].each { |l| l.send :include, ::Extensions }

Erubis::Context.send(:include, Extensions::Templates)

# Get all oneops elasticsearch-component's attributes and converting it to a hashmap
ci = node.workorder.rfcCi.ciAttributes
Chef::Log.info("Wiring OneOps ElasticSearch ci attributes : #{ci.to_json}")
$oneops_variables_hash = JSON.parse(ci.to_json.to_s)

# The memory is set in the node variable for using the es_jvm.erb template file later
node.set["elasticsearch_memory"] = ci["memory"]

# Obtaining details regarding the computes
fqdn_depends_on = node.workorder.payLoad.DependsOn.reject { |d| d['ciClassName'] != 'bom.Fqdn' }
computes = node.workorder.payLoad.has_key?('RequiresComputes')? node.workorder.payLoad.RequiresComputes : {}

# Setting the homedir for elasticsearch
home_dir = "/app/elasticsearch"

# Obtaining custom elasticsearch.yml file config and its jar file name
custom_elasticsearch_config = $oneops_variables_hash["custom_elasticsearch_config"]
jar_file_arr = custom_elasticsearch_config.split("/")
jar_file = jar_file_arr[jar_file_arr.length-1]



# Creating Elasticsearch Directories
Chef::Log.info("Creating the elasticsearch pid, logs, config, data, metadata and cronjobs directories")
bash 'Creating the elasticsearch pid, logs, config, data, metadata and cronjobs directories' do
  code <<-EOH
      sudo mkdir -p #{home_dir}/pid/ESNode
      sudo mkdir -p #{home_dir}/logs/ESNode
      sudo mkdir -p #{home_dir}/ESNode
      sudo mkdir -p #{home_dir}/data/ESNode
      sudo mkdir -p #{home_dir}/metadata
      sudo mkdir -p #{home_dir}/cronjobs
  EOH
end

# Changing ownership for Elasticsearch Directories
Chef::Log.info("Changing ownership for Elasticsearch Directory (recursively)")
bash 'Changing ownership for Elasticsearch Directories' do
  code <<-EOH
      sudo chown -R app:app #{home_dir}
  EOH
end

# Creating the metadata file for Oneops variables
Chef::Log.info("Creating the metadata file for Oneops variables")
ruby_block 'Creating the metadata file for Oneops variables' do
  block do
    $file = File.new("#{home_dir}/metadata/oneops_metadata.json", 'w')
    $file.write(JSON.pretty_generate($oneops_variables_hash).to_s)
    $file.close
  end
end


# Discovery Section
# Obtaining the computes from the current platform
Chef::Log.info("Obtaining the computes from the current platform")
number_of_computes = 0
unicastNodes = "["
computes.each do |cm|
  if !fqdn_depends_on.empty? && !cm[:ciAttributes][:hostname].nil?
    if unicastNodes == '['
      unicastNodes = cm[:ciAttributes][:hostname].to_s
      number_of_computes += 1
    else
      unicastNodes += ',' + cm[:ciAttributes][:hostname].to_s
      number_of_computes += 1
    end
  else
    unless cm[:ciAttributes][:private_ip].nil?
      if unicastNodes == '['
        hostname_info = `host #{cm[:ciAttributes][:private_ip]}`
        hostname_info_arr = hostname_info.split(" ")
        final_hostname = hostname_info_arr[hostname_info_arr.length-1].to_s
        unicastNodes = final_hostname[0..-2]
        number_of_computes += 1
      else
        hostname_info = `host #{cm[:ciAttributes][:private_ip]}`
        hostname_info_arr = hostname_info.split(" ")
        final_hostname = hostname_info_arr[hostname_info_arr.length-1].to_s
        unicastNodes += ',' + final_hostname[0..-2]
        number_of_computes += 1
      end
    end
  end
end

# Downloading and extracting elasticsearch.yml from proximity
Chef::Log.info("Downloading and extracting elasticsearch.yml from proximity --> Jar File #{jar_file}")
bash 'Download elasticsearch.yml from proximity' do
  code <<-EOH
          wget #{custom_elasticsearch_config} -P #{home_dir}/ESNode/
          cd #{home_dir}/ESNode/;jar -xvf #{home_dir}/ESNode/#{jar_file}
  EOH
end


# Updating the elasticsearch.yml file based on Master or Data Platforms
if $oneops_variables_hash["master"]=="true" and $oneops_variables_hash["data"]=="false"
  # If this is the master node

  # Now we will set the values for elasticsearch.yml file
  ruby_block 'Updating the elasticsearch.yml file with correct values for master node' do
    block do
      Chef::Log.info("Updating the elasticsearch.yml file with correct values")
      elasticsearch_yaml = YAML.load_file "#{home_dir}/ESNode/elasticsearch.yml"
      elasticsearch_yaml["discovery.zen.minimum_master_nodes"] = number_of_computes.to_s
      elasticsearch_yaml["discovery.zen.ping.unicast.hosts"] = unicastNodes.to_s
      elasticsearch_yaml["cluster.name"] = $oneops_variables_hash["cluster_name"]
      elasticsearch_yaml["node.data"] = $oneops_variables_hash["data"]
      elasticsearch_yaml["node.master"] = $oneops_variables_hash["master"]
      File.open("#{home_dir}/ESNode/elasticsearch.yml", 'w') { |f| YAML.dump(elasticsearch_yaml, f) }
    end
  end


elsif $oneops_variables_hash["master"]=="false" and $oneops_variables_hash["data"]=="true"

  # If this is a data node

  # Obtaining the fqdn of the elasticsearch-master platform
  hostname = `hostname -f` # elasticsearch.dev.assemply.org.cloud_name.prod.cloud.xyz.com
  hostname_parts = "#{hostname}".split('.') #convert above hostname string to array using hostname_delimiter
  index = 4
  hostname_arr = []
  # Removing <cloud_name> from hostname at index 4 as es_fqdn won't contain the same
  hostname_parts.delete_at(index)
  # Replace es-data hostname by es-master platform name. elasticsearch.xxxx.xxx => solr-zk.xxxx.xxx
  hostname_parts[0] = "elasticsearch-master"

  # Convert hostname array to '.' separated string. => elasticsearch-master.dev.assemply.org.prod.cloud.xyz.com
  es_fqdn = hostname_parts.join(".")
  # Now creating the hostnames from the fqdn
  ips = `host #{es_fqdn}`
  ips_arr = ips.split("\n") # list of all ips are obtained
  for ip_info in ips_arr
    ip_info_arr = ip_info.split(" ") # each line provides a bunch of info like: `solr-zk.prod-az-westus.limo-audit-prod.ms-df-solrcloud.prod.us.walmart.net has address 10.12.11.55`
    final_ip = ip_info_arr[ip_info_arr.length-1] # Taking the last part of the above line which is the `ip`
    hostname_info = `host #{final_ip}` # Using host on that same ip which gives info like: `58.11.12.10.in-addr.arpa domain name pointer solr-zk-358735198-3-488301970.prod-az-westus.limo-audit-prod.ms-df-solrcloud.prod-az-westus-1.prod.us.walmart.net.`
    hostname_info_arr = hostname_info.split(" ") # getting it space separated
    final_hostname = hostname_info_arr[hostname_info_arr.length-1].to_s  # Taking the last part which is the hostname
    hostname_arr.push(final_hostname[0..-2]) # Finally pushing it into the list
  end

  min_master_nodes = hostname_arr.length.to_i
  min_master_nodes = min_master_nodes/2 + 1


  # Adding all the hostnames in the unicastNodes list
  for individual_hostname in hostname_arr
    unicastNodes += ',' + individual_hostname
  end


  # Now we will set the values for elasticsearch.yml file
  ruby_block 'Updating the elasticsearch.yml file with correct values for data nodes' do
    block do
        Chef::Log.info("Updating the elasticsearch.yml file with correct values")
        elasticsearch_yaml = YAML.load_file "#{home_dir}/ESNode/elasticsearch.yml"
        elasticsearch_yaml["discovery.zen.minimum_master_nodes"] = min_master_nodes.to_s
        elasticsearch_yaml["discovery.zen.ping.unicast.hosts"] = unicastNodes.to_s
        elasticsearch_yaml["cluster.name"] = $oneops_variables_hash["cluster_name"]
        elasticsearch_yaml["node.data"] = $oneops_variables_hash["data"]
        elasticsearch_yaml["node.master"] = $oneops_variables_hash["master"]
        File.open("#{home_dir}/ESNode/elasticsearch.yml", 'w') { |f| YAML.dump(elasticsearch_yaml, f) }
    end
  end


end

# Creating a cron job for the master nodes to get the fqdn of elasticsearch-data and then change the configuration if that is true
Chef::Log.info("Creating the cronjob based ruby file")
template "#{home_dir}/cronjobs/update_elasticsearch_config.rb" do
  owner "app"
  group "app"
  mode '0755'
  source 'update_elasticsearch_config.erb'
end

# Activating update elasticsearch config cronjob
Chef::Log.info("Activating update elasticsearch config cronjob")
cron 'update elasticsearch config' do
  minute '*/5'
  command 'sudo ruby /app/elasticsearch/cronjobs/update_elasticsearch_config.rb'
end

# Creating sysconfig_es file
Chef::Log.info("Creating sysconfig_es file")
template "/etc/sysconfig/ESNode_elasticsearch" do
  owner "app"
  group "app"
  mode '0755'
  source 'sysconfig_es.erb'
end

# Creating elasticsearch_service file
Chef::Log.info("Creating elasticsearch_service file")
template "/usr/lib/systemd/system/ESNode_elasticsearch.service" do
  owner "app"
  group "app"
  mode '0755'
  source 'elasticsearch_service.erb'
end

# Creating jvm options file
Chef::Log.info("Creating jmv.options file")
template "#{home_dir}/ESNode/jvm.options" do
  owner "app"
  group "app"
  mode '0755'
  source 'es_jvm.erb'
end

# Creating log4j2 properties file
Chef::Log.info("Creating log4j2 properties file")
template "#{home_dir}/ESNode/log4j2.properties" do
  owner "app"
  group "app"
  mode '0755'
  source 'es_log4j2.erb'
end

# Downloading ES from proximity
Chef::Log.info("Downloading Elasticsearch rpm file from proximity")
current_es_version = $oneops_variables_hash["version"]
bash 'Downloading Elasticsearch rpm file' do
  code <<-EOH
      sudo yum -y install https://repository.walmart.com/repository/elastic-downloads/elasticsearch/elasticsearch-#{current_es_version}.rpm
  EOH
end

# Removing the earlier files obtained while installing ES by default
Chef::Log.info("Removing the earlier files obtained while installing ES by default")
bash 'Removing the earlier files obtained while installing ES by default' do
  code <<-EOH
      sudo rm /etc/init.d/elasticsearch
      sudo rm /etc/sysconfig/elasticsearch
  EOH
end

# Creating the /etc/sysconfig/elasticsearch file
Chef::Log.info("Creating the /etc/sysconfig/elasticsearch file")
bash 'Creating the /etc/sysconfig/elasticsearch file' do
  code <<-EOH
      sudo touch /etc/sysconfig/elasticsearch
      sudo chown app:app /etc/sysconfig/elasticsearch
  EOH
end

# Symbolic Link to Service file
Chef::Log.info("Creating the Symbolic Link to the service file")
bash 'Creating the Symbolic Link to the service file' do
  code <<-EOH
      sudo rm /usr/lib/systemd/system/elasticsearch.service
      sudo ln -sf /usr/lib/systemd/system/ESNode_elasticsearch.service /usr/lib/systemd/system/elasticsearch.service
  EOH
end

# Removing default files
Chef::Log.info("Removing default config files obtained with default es install")
bash 'Removing default config files obtained with default es install' do
  code <<-EOH
      sudo rm /etc/elasticsearch/elasticsearch.yml
      sudo rm /etc/elasticsearch/log4j2.properties
      sudo rm /etc/elasticsearch/jvm.options
  EOH
end

# Setting vm.max_map_count
Chef::Log.info("Setting vm.max_map_count")
bash 'Setting vm.max_map_count' do
  code <<-EOH
      echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
      sudo systemctl daemon-reload
      sudo sysctl -w vm.max_map_count=262144
  EOH
end

# Restarting Elasticsearch
Chef::Log.info("Restarting Elasticsearch...")
bash 'Restarting Elasticsearch...' do
  code <<-EOH
      sudo service elasticsearch restart
  EOH
end