require "/opt/solr-recipes/replica-distributor/solr_apis.rb"
require 'json'

include_recipe 'solr-collection::default'

Chef::Log.info("Including the replica distibutor from external source")
Chef::Log.info("*** Placing replicas for #{node['collection_name']} ***")

cloud_provider = CloudProvider.new(node)
clouds_payload = cloud_provider.get_clouds_payload(node)
computes_payload = CloudProvider.get_computes_payload(node)

# 4 cases for Node sharing Option
# 1. Share the IPs of the collections which is listed in node['collections_for_node_sharing']
# 2. [] -> Do not share any IP which is already part of any existing collection
# 3. [NO_OP_BY_DEFAULT] -> Apply the replica distribution normally without any filtering of IPs
# 4. If User doesn't provide any values -> consider it as NO_OP_BY_DEFAULT
collections_for_node_sharing = JSON.parse(node['collections_for_node_sharing'])
collections_for_node_sharing.collect! {|collection_name| collection_name.strip }
collections_for_node_sharing = collections_for_node_sharing.reject {|coll| coll == node['collection_name']}
if collections_for_node_sharing.size > 1
    collections_for_node_sharing = collections_for_node_sharing.reject {|coll| coll == 'NO_OP_BY_DEFAULT'}
end

collection_specs = []

collection = {
    "coll_name" => node['collection_name'],
    "num_shards" => node['num_shards'].to_i,
    "num_replicas" => node['replication_factor'].to_i,
    "collections_for_node_sharing" => collections_for_node_sharing
}

collection_specs.push(collection)

port_no = node['port_num'].to_i

complete_payload = {
    "clouds_payload" => clouds_payload,
    "computes_payload" => computes_payload,
    "collection_specs" => collection_specs,
    "port_no" => port_no
}

Chef::Log.info("the replica distibutor payload -- #{complete_payload}")

solr_replica_distributor(complete_payload)
