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
    it 'should have the same public/private IP address' do
      rg_svc = AzureBase::ResourceGroupManager.new($node)
      ci_id = $node['workorder']['rfcCi']['ciId']

      cloud_name = $node['workorder']['cloud']['ciName']
      compute_service = $node['workorder']['services']['compute'][cloud_name]['ciAttributes']
      ip_type = (compute_service['express_route_enabled'].eql? 'true') ? 'private' : 'public'

      if ip_type.eql? 'public'
        public_ip_node = $node['workorder']['rfcCi']['ciAttributes']['public_ip']

        pip = AzureNetwork::PublicIp.new(@spec_utils.get_azure_creds)
        public_ip_name = Utils.get_component_name('publicip', ci_id)
        public_ip = pip.get(rg_svc.rg_name, public_ip_name)

        expect(public_ip_node).to eq(public_ip.ip_address)
      else
        private_ip_node = $node['workorder']['rfcCi']['ciAttributes']['private_ip']

        nic_svc = AzureNetwork::NetworkInterfaceCard.new(@spec_utils.get_azure_creds)
        nic_svc.ci_id = ci_id
        nic_svc.platform_ci_id = $node['workorder']['box']['ciId'] if Utils.is_new_cloud($node)
        nic_svc.rg_name = rg_svc.rg_name
        nic_name = Utils.get_component_name('nic', nic_svc.ci_id, nic_svc.platform_ci_id)
        nic = nic_svc.get(nic_name)

        expect(private_ip_node).to eq(nic.private_ip_address)
      end
    end
  end
end
