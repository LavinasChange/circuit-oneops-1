
# Copyright 2016, Walmart Stores, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# storage::add
#
# adds block storage ... volume component will attach and create raid device and filesystem
#


# TODO: fix fog/aws devices to remove the /dev/[s|vx]d\d+ limitation
# only 15*8 devices available from sdi1-sdp15 (efgh used for ephemeral)
#

require 'json'
include_recipe 'shared::set_provider_new'

rfcCi = node[:workorder][:rfcCi]
ciAttr = rfcCi[:ciAttributes]
action = rfcCi[:rfcAction]
provider = node['storage_provider_class']

if node.workorder.has_key?("payLoad") && node.workorder.payLoad.has_key?("volumes")
  mode = node.workorder.payLoad.volumes[0].ciAttributes["mode"]
else
  mode = "no-raid"
end

size = size_g(ciAttr['size'])
if action == 'update' && mode != 'no-raid'
  exit_with_error('RAID expansion is not supported')
end

# Functionality encapsulated in a class, provider specific methods
# are implemented separately for different providers
storage = StorageComponent::Storage.new(node)
old_size = storage.total_size_gb
Chef::Log.info("Storage size requested: #{size}G, current size is #{old_size}G")
if old_size > size
  exit_with_error('Cannot decrease storage size, please roll back')
elsif old_size == size
  Chef::Log.info('Storage size is not changing, skipping the deployment')
  puts "***RESULT:device_map="+storage.device_map.join(" ")
  return
else
  size = size - old_size
end

initial_slice_count = ciAttr[:slice_count].to_i
actual_slice_count = storage.storage_devices.size
slice_count = initial_slice_count - (actual_slice_count % initial_slice_count)
final_slice_count = initial_slice_count * (actual_slice_count.to_i / initial_slice_count + 1)

if slice_count == 1
  slice_size = size.to_i
elsif mode == "no-raid" || mode == "raid0"
  slice_size = (size.to_f / slice_count.to_f).ceil
elsif mode == "raid1" || mode == "raid10"
  slice_size = (size.to_f / slice_count.to_f).ceil * 2
elsif mode == "raid5"
  slice_size = size.to_f/(slice_count.to_i-1).ceil
end

Chef::Log.info("Adding storage: #{size}GB total, #{slice_count} slices of #{slice_size}GB each")
if slice_size < 10 && provider =~ /cinder/
  exit_with_error("Minimum slice size should be 10G for #{provider}")
end

# openstack+kvm doesn't use explicit device names, just set and order
block_index = ""
["p","o","n","m","l","k","j","i"].each do |i|
  dev = "/dev/vxd#{i}0"
  if !::File.exists?(dev)
    block_index = i
    break
  end
end

# TO-DO replace the following functionality with a new method in Storage class
Array(actual_slice_count+1..final_slice_count).each do |i|

  if provider =~ /cinder|azure/
    dev = storage.planned_device_id(i)
  else
    dev = "/dev/xvd#{block_index}#{i.to_s}"
  end
  Chef::Log.info("Adding dev: #{dev} size: #{slice_size}G with provider #{provider}")

  volume = nil
  case provider
  when /cinder/
    begin
      include_recipe 'storage::node_lookup'
      vol_name = rfcCi[:ciName] + "-" + rfcCi[:ciId].to_s
      Chef::Log.info("Volume type selected in the storage component:"+node.volume_type_from_map)
      Chef::Log.info("Creating volume of size:#{slice_size} , volume_type:#{node.volume_type_from_map}, volume_name:#{vol_name} .... ")
      volume = node.storage_provider.volumes.new :size => slice_size, :name => vol_name,
        :description => dev, :display_name => vol_name, :volume_type => node.volume_type_from_map
      volume.save
    rescue Excon::Errors::RequestEntityTooLarge => e
      exit_with_error(JSON.parse(e.response[:body])["overLimit"]["message"])
    rescue Exception => e
      exit_with_error(e.message)
    end

  when /rackspace/
    begin
      vol_name = rfcCi[:ciName] +"-" + rfcCi[:ciId].to_s
      volume = node.storage_provider.volumes.new :display_name => vol_name, :size => slice_size.to_i
      volume.save
    rescue Exception => e
      Chef::Log.info("exception: "+e.inspect)
    end
  when /ibm/
    volume = node.storage_provider.volumes.new({
      :name => rfcCi[:ciName],
      :format => "RAW",
      :location_id => "41",
      :size => "60",
      :offering_id => "20035200"
    })
    volume.save
    # takes ~5min, lets sleep 1min, then try for 10min to wait for Detached state,
    # because volume::add will error if not in Detached state
    sleep 60
    max_retry_count = 10
    retry_count = 0
    vol = node.storage_provider.volumes.get volume.id
    while vol.state != "Detached" && retry_count < max_retry_count
      sleep 60
      vol = node.storage_provider.volumes.get volume.id
      retry_count += 1
      Chef::Log.info("vol state: "+vol.state)
    end

    if retry_count >= max_retry_count
      Chef::Log.error("took more than 10minutes for volume: "+volume.id.to_s+" to be ready and still isn't")
    end

    when /azuredatadisk/

      #set the proxy if it exists as a cloud var
      Utils.set_proxy(node[:workorder][:payLoad][:OO_CLOUD_VARS])

      rg_manager = AzureBase::ResourceGroupManager.new(node)
      as_manager = AzureBase::AvailabilitySetManager.new(node)

      compute_attr = node[:workorder][:payLoad][:DependsOn].select{|d| (d[:ciClassName].split('.').last == 'Compute') }.first[:ciAttributes]
      vm = node[:storage_provider].servers(:resource_group => rg_manager.rg_name).get(rg_manager.rg_name, compute_attr[:instance_name])

      if vm.vm_size =~ /.*[EDG](\d+|)S.*/i && %w(IOPS1 IOPS2).include?(ciAttr[:volume_type])
        account_type = 'Premium_LRS'
      else
        account_type = 'Standard_LRS'
      end
      vol_name = rfcCi[:ciName] + '-' + rfcCi[:ciId].to_s + '-' + i.to_s

      availability_set_response = node[:storage_provider].availability_sets.get(rg_manager.rg_name, as_manager.as_name)

      if availability_set_response.sku_name == 'Aligned'
        volume = node.storage_provider.managed_disks.create(
          :name                => vol_name,
          :location            => rg_manager.location,
          :resource_group_name => rg_manager.rg_name,
          :account_type        => account_type,
          :disk_size_gb        => slice_size,
          :creation_data       => { :create_option => 'Empty' }
        )
        Chef::Log.info("Managed disk created: #{volume.inspect.gsub("\n",'')}")
        volume_dev = [vol_name, dev].join(':')
      else
        #The old way - unmanaged disk
        storage_account_name = vm.storage_account_name
        vhd_blobname = [storage_account_name,rfcCi[:ciId].to_s,'datadisk',dev.split('/').last.to_s].join('-')

        storage_service = get_azure_storage_service(rg_manager.creds, rg_manager.rg_name, storage_account_name)
        storage_service.create_disk(vhd_blobname, slice_size.to_i, options = {})
        volume_dev = [rg_manager.rg_name, storage_account_name, rfcCi[:ciId].to_s, slice_size.to_s, dev].join(':')
      end #if availability_set_response.sku_name == 'Aligned'

    else
    # aws
    avail_zone = ''
    node.storage_provider.describe_availability_zones.body['availabilityZoneInfo'].each do |az|
      puts "az: #{az.inspect}"
      if az['zoneState'] == 'available'
        avail_zone = az['zoneName']
        break
      end
    end
    volume = node.storage_provider.volumes.new :device => dev, :size => slice_size, :availability_zone => avail_zone
  end

  if provider !~ /azuredatadisk/
    volume_dev = volume.id.to_s + ':' + dev
  end
  Chef::Log.info("Adding #{volume_dev} to device map")
  device_entry = {
    'id'      => volume_dev.split(':')[0..-2].join(':'),
    'size_gb' => slice_size
  }
  storage.storage_devices.push(device_entry)
end

puts "***RESULT:device_map="+storage.device_map.join(" ")
