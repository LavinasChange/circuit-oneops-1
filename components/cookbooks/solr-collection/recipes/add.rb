#
# Cookbook Name :: solr-collection
# Recipe :: add.rb
#
#
#

include_recipe 'solr-collection::default'
include_recipe 'solr-collection::schedule_backup'
if node.workorder.has_key?("rfcCi")
  ci = node.workorder.rfcCi.ciAttributes
else
  ci = node.workorder.ci.ciAttributes
end
skip_compute = node['skip_compute']
if skip_compute > 0
  Chef::Log.info("solr-collection will not run on this compute")
  return
end

if node['action_name'] == 'replace'
  node['skip_collection_comp_execution'] == "true"
end

if (node['skip_collection_comp_execution'] == "true")
    Chef::Log.info("Skipping execution of solr-collection component. Since skip_collection_comp_execution flag is enabled.")
    return
end

Chef::Log.info('Create xmldiffs.py script file to perform diff between xml files')
template "/tmp/xmldiffs.py" do
  source 'xmldiffs.py'
  owner node['solr']['user']
  group node['solr']['user']
  mode '0777'
  mode '0777'
  not_if { ::File.exists?("/tmp/xmldiffs.py") }
end
include_recipe 'solr-collection::upload_zk_config'
include_recipe 'solr-collection::collection'
include_recipe 'solr-collection::monitor'
include_recipe 'solr-collection::replica_distribution_checker'
