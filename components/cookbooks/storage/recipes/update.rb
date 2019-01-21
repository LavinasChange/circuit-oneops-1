Chef::Log.info('Storage Update .......')

rfcCi = node['workorder']['rfcCi']
v_device_map = rfcCi['ciAttributes']['device_map']
base = rfcCi['ciBaseAttributes']
cloud_name = node[:workorder][:cloud][:ciName]
storage_provider = node[:workorder][:services][:storage][cloud_name][:ciClassName].gsub("cloud.service.","").downcase.split(".").last
Chef::Log.info("Device Map: <#{v_device_map.to_s}>")

# There are several explicitly prohibited update scenarios, we have to raise an
# error so users know the update they asked for is not supported
if v_device_map && base.key?('volume_type')
  exit_with_error('Cannot change storage type for already deployed storage, please roll back.')
elsif v_device_map && base.key?('slice_count')
  exit_with_error('Cannot change slice count for already deployed storage, please roll back.')
elsif v_device_map && base.has_key?('size') && storage_provider !~ /cinder|azuredatadisk/
  exit_with_error("Cannot change storage size for #{storage_provider}, please roll back.")
else
  include_recipe 'storage::add'
end
