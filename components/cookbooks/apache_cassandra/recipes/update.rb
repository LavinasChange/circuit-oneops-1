#Check for upgrade
selected_version = node.workorder.rfcCi.ciAttributes.version
current_version = `/app/cassandra/current/bin/cassandra -v`
Chef::Log.info("current_version = #{current_version}")
Chef::Log.info("selected_version = #{selected_version}")
version_change = Gem::Version.new(current_version) <=> Gem::Version.new(selected_version) 
puts "Version_Change = #{version_change}"
unless version_change == 0 
    puts "***RESULT:node_version=" + current_version
    Chef::Log.info("Upgrade/Downgrade detected. Exiting. Please run upgrade action in operations")
    return  #Stop the recipe
end

include_recipe "apache_cassandra::add"