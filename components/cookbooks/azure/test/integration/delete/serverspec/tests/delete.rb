COOKBOOKS_PATH ||= '/opt/oneops/inductor/circuit-oneops-1/components/cookbooks'.freeze

require 'chef'
require 'fog/azurerm'
(
Dir.glob("#{COOKBOOKS_PATH}/azure/libraries/*.rb") +
    Dir.glob("#{COOKBOOKS_PATH}/azure_base/libraries/*.rb")
).each { |lib| require lib }

#load spec utils
require "#{COOKBOOKS_PATH}/azure_base/test/integration/azure_spec_utils"

describe "azure vm::delete" do
  before(:each) do
    @spec_utils = AzureSpecUtils.new($node)
    @credentials = @spec_utils.get_azure_creds
    @rg_svc = AzureBase::ResourceGroupManager.new($node)
    @resource_group_name = @rg_svc.rg_name
  end

  context 'virtual machine' do
    it 'should not exist' do
      virtual_machine_svc = AzureCompute::VirtualMachine.new(@credentials)
      server_name = @spec_utils.get_server_name
      exists = virtual_machine_svc.check_vm_exists?(@resource_group_name, server_name)

      expect(exists).to eq(false)
    end
  end

  context 'managed os disk' do
    it 'should not exist' do
      azure_compute_svc = Fog::Compute::AzureRM.new(@credentials)
      os_disk_exists = azure_compute_svc.managed_disks.check_managed_disk_exists(@resource_group_name, @spec_utils.get_os_disk_name)

      expect(os_disk_exists).to eq(false)
    end
  end

  context 'nic' do
    it 'should not exist' do
      nic_svc = Fog::Network::AzureRM.new(@credentials)

      nic_ci_id = $node['workorder']['rfcCi']['ciId']
      nic_platform_ci_id = $node['workorder']['box']['ciId'] if Utils.is_new_cloud($node)
      nic_name = Utils.get_component_name('nic', nic_ci_id, nic_platform_ci_id)
      nic_exists = nic_svc.check_network_interface_exists(@resource_group_name, nic_name)

      expect(nic_exists).to eq(false)
    end
  end
end