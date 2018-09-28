Chef::Log.info("lookup service mesh yaml...")
execute 'startServiceMesh' do
	command "#{node['service-mesh']['init-name']} restart"
	user	'root'
end

linkerdConfigPath = ""

if(node['service-mesh']['use-overridden-yaml'] == "true")
	linkerdConfigPath = "#{node['service-mesh']['service-mesh-root']}" + "/overridden-config.yaml"
else
	linkerdConfigPath = "#{node['service-mesh']['service-mesh-root']}" + "/linkerd-sr.yaml"
end

Chef::Log.info("\n"+ File.read(linkerdConfigPath) + "\</pre\>\n")

Chef::Log.info("action lookup service mesh yaml ran successfully.")
