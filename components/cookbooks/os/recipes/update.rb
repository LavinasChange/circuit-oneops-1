#
# Cookbook Name:: os
# Recipe:: update
#
if (node[:workorder][:rfcCi][:ciBaseAttributes].has_key?("ostype") &&
    (node[:workorder][:rfcCi][:ciBaseAttributes][:ostype] != node[:workorder][:rfcCi][:ciAttributes][:ostype]))
  exit_with_error "OS type doens't match with current configuration, consider replacing compute or change OS type to original"
elsif is_propagate_update
  puts "***RESULT:tags="+JSON.dump({"security" => Time.now.utc.iso8601})

  include_recipe "os::add-conf-files"
else
  include_recipe "os::add"
end
