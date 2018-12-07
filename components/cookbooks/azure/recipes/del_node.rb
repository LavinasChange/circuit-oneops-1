require File.expand_path('../../../azure_base/libraries/logger.rb', __FILE__)
require 'fog/azurerm'

# set the proxy if it exists as a cloud var
Utils.set_proxy(node.workorder.payLoad.OO_CLOUD_VARS)

# get platform resource group and availability set
include_recipe 'azure::get_platform_rg_and_as'

# delete the VM
vm_client = AzureCompute::VirtualMachineManager.new(node)
storage_account, vhd_uri, datadisk_uri = vm_client.delete_unmanaged_vm if vm_client.availability_set_response.sku_name.eql? 'Classic'
os_disk, datadisk_uri = vm_client.delete_vm if vm_client.availability_set_response.sku_name.eql? 'Aligned'


# TODO when managed data disk service re written we need to revist the storage_account name
node.set['storage_account'] = storage_account if vm_client.availability_set_response.sku_name.eql? 'Classic' # storage account means here managed os disk

# to delete the managed OS disk
if vm_client.availability_set_response.sku_name == 'Aligned'
  vm_storage_profile = AzureCompute::StorageProfile.new(vm_client.creds) 
  vm_storage_profile.delete_managed_osdisk(vm_client.resource_group_name, os_disk)

  # ensure that the deleted managed disk completely vanishes and does not show up in the 'list_resources' method
  rg_manager = AzureBase::ResourceGroupManager.new(node)

  max_retries = 6
  counter = 0

  loop do
    resources = rg_manager.list_resources
    break unless resources.any? { |resource| resource.name.eql? os_disk }
    exit_with_error 'Managed Disk Still Exists After Max Retries. Exiting!' if counter == max_retries

    OOLog.info('Managed Disk Still Getting Listed After Deletion. Sleeping for 20 Seconds...')
    sleep 20
    counter += 1
  end

  OOLog.info('Managed Disk Deleted Successfully!')
end


node.set['vhd_uri'] = vhd_uri
node.set['datadisk_uri'] = datadisk_uri

# delete the NIC. A NIC is created with each VM, so we will delete the NIC when we delete the VM
nic_platform_ci_id = node['workorder']['box']['ciId'] if Utils.is_new_cloud(node)
nic_name = Utils.get_component_name('nic', vm_client.compute_ci_id, nic_platform_ci_id)
network_profile = AzureNetwork::NetworkInterfaceCard.new(vm_client.creds)
network_profile.delete(vm_client.resource_group_name, nic_name)

# public IP must be deleted after the NIC.
if vm_client.ip_type == 'public'
  public_ip_name = Utils.get_component_name('publicip', vm_client.compute_ci_id)
  public_ip = AzureNetwork::PublicIp.new(vm_client.creds)
  public_ip.delete(vm_client.resource_group_name, public_ip_name)
end


# delete the blobs
# Delete both Page blob(vhd) and Block Blob from the storage account
# Delete both osdisk and datadisk blob - TO-DO delete blobs correctly when VM is already deleted, and its attributes are unavailable
if (vm_client.availability_set_response.sku_name.eql? 'Classic') && !storage_account.nil? && !vhd_uri.nil?
 include_recipe 'azure::del_blobs'
end
# need to taken care enhancing the Fogcode for managed data disk

OOLog.info('Exiting azure delete compute')
