=begin
This spec has tests that validates a successfully completed oneops-azure deployment
=end

COOKBOOKS_PATH ||= '/opt/oneops/inductor/circuit-oneops-1/components/cookbooks'.freeze

require 'chef'
require 'fog/azurerm'
(
Dir.glob("#{COOKBOOKS_PATH}/azure/libraries/*.rb") +
    Dir.glob("#{COOKBOOKS_PATH}/azure_base/libraries/*.rb")
).each { |lib| require lib }

# load spec utils
require "#{COOKBOOKS_PATH}/azure_base/test/integration/azure_spec_utils"

describe 'azure node::update' do
  before(:each) do
    @spec_utils = AzureSpecUtils.new($node)
  end

  context 'Compute' do
    it 'should have the same public & private IP address' do
      public_ip_node = $node['workorder']['rfcCi']['ciAttributes']['public_ip']
      private_ip_node = $node['workorder']['rfcCi']['ciAttributes']['private_ip']

      rg_svc = AzureBase::ResourceGroupManager.new($node)
      ci_id = $node['workorder']['rfcCi']['ciId']

      nic_svc = AzureNetwork::NetworkInterfaceCard.new(@spec_utils.get_azure_creds)
      nic_svc.ci_id = ci_id
      nic_svc.platform_ci_id = $node['workorder']['box']['ciId'] if Utils.is_new_cloud($node)
      nic_svc.rg_name = rg_svc.rg_name
      nic_name = Utils.get_component_name('nic', nic_svc.ci_id, nic_svc.platform_ci_id)
      nic = nic_svc.get(nic_name)

      pip = AzureNetwork::PublicIp.new(@spec_utils.get_azure_creds)
      public_ip_name = Utils.get_component_name('publicip', ci_id)
      publicip_details = pip.get(rg_svc.rg_name, public_ip_name)
      pubip_address = publicip_details.ip_address

      expect(public_ip_node).to eq(pubip_address)
      expect(private_ip_node).to eq(nic.private_ip_address)
    end
  end
end
