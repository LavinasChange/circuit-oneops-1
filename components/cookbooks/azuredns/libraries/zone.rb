require 'chef'
require ::File.expand_path('../../../azure_base/libraries/logger', __FILE__)

# **Rubocop Suppression**
# rubocop:disable MethodLength
# rubocop:disable LineLength
# rubocop:disable AbcSize

module AzureDns
  # DNS Zone Class
  class Zone

    attr_accessor :dns_client

    def initialize(dns_attributes, resource_group)
      credentials = {
          tenant_id: dns_attributes[:tenant_id],
          client_secret: dns_attributes[:client_secret],
          client_id: dns_attributes[:client_id],
          subscription_id: dns_attributes[:subscription]
      }
      @dns_client = Fog::DNS::AzureRM.new(credentials)
      @resource_group = resource_group
      @zone_name = dns_attributes[:zone]
    end

    def check_for_zone
      start_time = Time.now.to_i
      begin
        zone_exists = @dns_client.zones.check_zone_exists(@resource_group, @zone_name)
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("FATAL ERROR getting DNS Zone....: #{e.body}")
      rescue => e
        return false if e == 'ResourceNotFound'
      end
      end_time = Time.now.to_i
      duration = end_time - start_time
      puts "***TAG:az_check_zone=#{duration}" if ENV['KITCHEN_YAML'].nil?
      if zone_exists
        OOLog.info("AzureDns:Zone - Zone Exists in the Resource Group: #{@resource_group}. No need to create ")
        true
      else
        false
      end
    end

    def create
      OOLog.info("AzureDns:Zone - Creating Zone: #{@zone_name} in the Resource Group: #{@resource_group}.")
      start_time = Time.now.to_i
      begin
        zone = @dns_client.zones.create(resource_group: @resource_group, name: @zone_name, location: 'global')
      rescue MsRestAzure::AzureOperationError => e
         OOLog.fatal("FATAL ERROR creating DNS Zone....: #{e.body}")
      rescue => e
        OOLog.fatal("DNS Zone creation error....: #{e.message}")
      end
      end_time = Time.now.to_i
      duration = end_time - start_time
      puts "***TAG:az_create_zone=#{duration}" if ENV['KITCHEN_YAML'].nil?
      zone
    end
  end
end
