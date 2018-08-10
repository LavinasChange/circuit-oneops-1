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

# Cookbook Name:: fqdn
# Recipe:: set_dns_entries
#
# uses node[:entries] list of dns entries based on entrypoint, aliases, zone, and platform to update dns
# no ManagedVia - recipes will run on the gw

extend Fqdn::Base
Chef::Resource::RubyBlock.send(:include, Fqdn::Base)


def delete_record (dns_name, dns_value)

  delete_type = get_record_type(dns_name,[dns_value])

  Chef::Log.info("delete #{delete_type}: #{dns_name} to #{dns_value}")

  api_version = "v1.0"

  record = { :name => dns_name.downcase }
  case delete_type
    when "cname"
      record["canonical"] = dns_value.downcase
    when "a"
      record["ipv4addr"] = dns_value.downcase
    when "aaaa"
      record["ipv6addr"] = dns_value.downcase
    when "ptr"
      if dns_name =~ Resolv::IPv4::Regex
        record = {"ipv4addr" => dns_name,
                  "ptrdname" => dns_value}
      elsif dns_name =~ Resolv::IPv6::Regex
        record = {"ipv6addr" => dns_name,
                  "ptrdname" => dns_value}
        api_version = "v1.2" #ipv6addr attribute is recognized only in infoblox api version >= 1.1
      end
    when "txt"
      record = {"name" => dns_name,
                "text" => dns_value}
  end

  records = JSON.parse(node.infoblox_conn.request(:method=>:get,
    :path=>"/wapi/#{api_version}/record:#{delete_type}", :body => JSON.dump(record) ).body)

  if records.size == 0
    Chef::Log.info("record already deleted")

  else
    records.each do |r|
      ref = r["_ref"]
      resp = node.infoblox_conn.request(:method => :delete, :path => "/wapi/#{api_version}/#{ref}")
      Chef::Log.info("status: #{resp.status}")
      if (resp.status.to_i != 200)
        Chef::Log.error("response: #{resp.inspect}")
      else
        Chef::Log.debug("response: #{resp.inspect}")
      end
    end
  end
end


def handle_response (resp_obj)
  
  Chef::Log.debug("response: #{resp_obj.inspect}")
  infoblox_resp_obj = resp_obj.inspect
  begin
    infoblox_resp_obj = JSON.parse(resp_obj.body)
    Chef::Log.info("infoblox response obj: #{infoblox_resp_obj.inspect}")
  rescue
    # ok - non formated response
  end
  
  if infoblox_resp_obj.class.to_s != "String" && infoblox_resp_obj.has_key?("Error")
    if infoblox_resp_obj.has_key?('text')
      fail_with_fault infoblox_resp_obj['text']                 
    else
      fail_with_fault infoblox_resp_obj.inspect
    end
  end
end  


def set_is_hijackable_record(dns_name)
  
  # 'txt-' prefix due to cnames and txt records cannot exist for same name in infoblox 
  record = { :name => 'txt-' + dns_name, :text => "hijackable_from_#{get_customer_domain}" }
  
  records = JSON.parse(node.infoblox_conn.request(:method=>:get,
    :path=>"/wapi/v1.0/record:txt", :body => JSON.dump(record) ).body)

  if records.size == 0
    Chef::Log.info("creating txt record: #{record.inspect}")
    handle_response node.infoblox_conn.request(
      :method => :post,
      :path => "/wapi/v1.0/record:txt",
      :body => JSON.dump(record))
        
    Chef::Log.info("created record: #{record.inspect}")
  else
    Chef::Log.info("exists record: #{record.inspect}")    
  end
 
end




include_recipe "fqdn::get_infoblox_connection"

view_attribute = get_dns_service[:view_attr]

Chef::Log.debug("view_attribute: #{view_attribute}")

ns = node.ns

deletable_values = []
if node.has_key?("deletable_entries")
  node.deletable_entries.each do |deletable_entry|
    if deletable_entry[:values].is_a?(String)
      deletable_values.push(deletable_entry[:values])
    else
      deletable_values += deletable_entry[:values]
    end
  end
end

deletable_values.uniq!

#
# delete / create dns entries
#

# while enabling gdn on exiting platform
# delete if 'a' record exist for primary_platform_dns_name pointing to LB ips
if node.has_key?("gslb_domain") && !node.gslb_domain.nil?
  node.workorder.payLoad[:lb].each do |comp|
    delete_record(node.primary_platform_dns_name,comp["ciAttributes"]["dns_record"])
  end
end

node[:entries].each do |entry|
  dns_match = false
  dns_name = entry[:name]
  dns_values = entry[:values].is_a?(String) ? Array.new([entry[:values]]) : entry[:values]

  dns_type = get_record_type(dns_name,dns_values)

  if dns_name.empty? || dns_name =~ /^\*$/
   Chef::Log.error("invalid dns_name: #{dns_name}")
   exit 1
  end

  # put a value for wildcard dns entries
  dns_name_for_lookup = dns_name.gsub("\*","abc123")
  Chef::Log.info("#{dns_name_for_lookup} new values: "+dns_values.sort.inspect)

  existing_dns = get_existing_dns(dns_name,ns)

  Chef::Log.info("previous entries: #{node.previous_entries}")
  Chef::Log.info("deletable_values: #{deletable_values}")
  
  
  # is_hijackable only set on full_aliases
  if entry.has_key?(:is_hijackable)    
    if node.workorder.rfcCi.ciAttributes.hijackable_full_aliases == 'true'
      set_is_hijackable_record(dns_name)
    elsif node.workorder.rfcCi.ciBaseAttributes.has_key?('hijackable_full_aliases') &&
      node.workorder.rfcCi.ciBaseAttributes.hijackable_full_aliases == 'true'
      delete_record('txt-' + dns_name,"hijackable_from_#{get_customer_domain}")
    end
  end
    
  if existing_dns.length > 0 || node[:dns_action] == "delete"
    
    # cleanup or delete
    existing_dns.each do |existing_entry|
      value = node.deletable_entries.detect{ |d| d[:name] == dns_name }
      if !value.nil? && value[:values].include?(existing_entry) && (
      (dns_values.include?(existing_entry) && node[:dns_action] == "delete") ||
          # value was in previous entry, but not anymore
          (!dns_values.include?(existing_entry) &&
              node.previous_entries.has_key?(dns_name) &&
              node.previous_entries[dns_name].include?(existing_entry) &&
              node[:dns_action] != "delete")) ||
          # hijackable cname - remove unknown value
          (entry.has_key?(:is_hijackable) && is_hijackable(dns_name,ns) && !dns_values.include?(existing_entry))

        delete_record(dns_name, existing_entry)
      end

      # First check to make sure we have dc_entry attribute
      if node[:dc_entry] 
        if dns_name.downcase.eql?(node[:dc_entry][:name].downcase)
          # Delete existing entry only if it's not dc_entry (active dc_entry)
          delete_record(dns_name, existing_entry) if !node[:dc_entry][:values].include?(existing_entry)
        end
      end
    end
  end

  # delete workorder skips the create call
  if node[:dns_action] == "delete"
    next
  end


  # infoblox has multiple record values for round-robin entries
  # View attribute extracted from infoblox metadata to make it configurable item
  dns_values.each do |dns_value|
    
    if existing_dns.include?(dns_value)
      Chef::Log.info("exists #{dns_type}: #{dns_name} to #{dns_values.to_s}")
      next        
    end
    
    Chef::Log.info("create #{dns_type}: #{dns_name} to #{dns_values.to_s}")
    
    ttl = 60
    if node.workorder.rfcCi.ciAttributes.has_key?("ttl")
      ttl = node.workorder.rfcCi.ciAttributes.ttl.to_i
    end
    
    record = {
       :name => dns_name.downcase,
       :view => view_attribute,
       :ttl => ttl
    }
    api_version = "v1.0"
    case dns_type
      when "cname"
        record[:canonical] = dns_value.gsub(/\.+$/,"")
      when "a"
        record[:ipv4addr] = dns_value
      when "aaaa"
        record[:ipv6addr] = dns_value.gsub(/\.+$/,"")
      when "ptr"
        if dns_name =~ Resolv::IPv6::Regex
          record[:ipv6addr] = dns_name
          api_version = "v1.2" #ipv6addr attribute is recognized only in infoblox api version >= 1.1
        elsif dns_name =~ Resolv::IPv4::Regex
          record[:ipv4addr] = dns_name
        end
        record.delete(:name)
        record[:ptrdname] = dns_value
        
    end

    Chef::Log.debug("record: #{record.inspect}")

    handle_response node.infoblox_conn.request(
      :method => :post,
      :path => "/wapi/#{api_version}/record:#{dns_type}",
      :body => JSON.dump(record))
    
  end
  if !verify(dns_name,dns_values,ns)
    fail_with_fault "could not verify: #{dns_name} to #{dns_values} on #{ns} after 5min."
  end
end


if node.has_key?("gslb_domain") && !node.gslb_domain.nil? &&
    node[:workorder].has_key?('config') && node[:workorder][:config].has_key?('delegation_enable') && node[:workorder][:config][:delegation_enable].to_s.downcase == "true"

  api_version = "v2.5"
  fqdn = node.gslb_domain
  base_domain = node.gslb_base_domain

  delegation_info = "/secrets/gslb_delegation.json"

  if ::File.exists?(delegation_info)

    data_json = JSON.parse(File.read(delegation_info))

    Chef::Log.info("Base domain : #{base_domain}")

    delegation_entry_flag = false
    delegation = nil

    data_json["delegation"].each do |record|
      if record["base_domain"] == base_domain

        if record.has_key?("excluded_domains") && record["excluded_domains"].size != 0
          valid_domain = true
          excluded_domains = record["excluded_domains"]

          excluded_domains.each do |domain|
            if fqdn.end_with?(domain)
              Chef::Log.info("skipping creation of delgations as #{fqdn} is in excluded domains")
              puts "***TAG:excluded_domain=#{fqdn}"
              valid_domain = false
              break
            end
          end

          if valid_domain
            delegation_entry_flag = true
            delegation = record["delegate_to"]
          end
          break
        else
          exit_with_error "Excluded domain info is missing"
        end
      end
    end

    if delegation_entry_flag

      #create connection with isd infoblox
      host = data_json["infoblox"]["host"]
      username = data_json["infoblox"]["username"]
      password = data_json["infoblox"]["password"]

      encoded = Base64.encode64("#{username}:#{password}").gsub("\n","")

      http_proxy = ENV['http_proxy']
      https_proxy = ENV['https_proxy']

      ENV['http_proxy'] = ''
      ENV['https_proxy'] = ''

      conn = Excon.new('https://'+host,
                       :headers => {'Authorization' => "Basic #{encoded}"}, :ssl_verify_peer => false)

      # Validate the connection.
      res =  conn.request(:method=>:get,:path=>"/wapi/v1.0/network")
      if(res.status != 200)
        raise res.body
      end

      # Set the connection object
      node.set["delegation_infoblox_conn"] = conn
      ENV['http_proxy'] = http_proxy
      ENV['https_proxy'] = https_proxy

      record_query = {
          "fqdn" => fqdn
      }

      if node.dns_action == "delete" && node.is_last_active_cloud
        Chef::Log.info("Deleting delegation entry : #{fqdn}")

        response = JSON.parse(node.delegation_infoblox_conn.request(
            :method => :get,
            :path => "/wapi/#{api_version}/zone_delegated",
            :body => JSON.dump(record_query)).body)

        if response.size != 0
          delete_query = response[0]['_ref']

          res = node.delegation_infoblox_conn.request(
              :method => :delete,
              :path => "/wapi/#{api_version}/#{delete_query}")

          if res.status == 200
            Chef::Log.info("Delegation entry for #{fqdn} deleted successfully #{res.inspect}")
          elsif res.status == 404
            Chef::Log.info("No record found for deletion #{res.inspect}")
          else
            exit_with_error "Error while deleting delegation record"
          end
        else
          Chef::Log.info("No record found for deletion")
        end

      else
        Chef::Log.info("Creating/updating delegation entry: #{fqdn}")

        response = JSON.parse(node.delegation_infoblox_conn.request(
            :method => :get,
            :path => "/wapi/#{api_version}/zone_delegated",
            :body => JSON.dump(record_query)).body)

        Chef::Log.info("Delegation data : #{delegation}")
        if response.size == 0
          record = {
              "fqdn" => fqdn,
              "delegate_to" => delegation,
              "delegated_ttl" => 30
          }
          Chef::Log.info("Record : #{record}")

          res = node.delegation_infoblox_conn.request(
              :method => :post,
              :path => "/wapi/#{api_version}/zone_delegated",
              :body => JSON.dump(record))

          if(res.status == 201)
            Chef::Log.info("Delegation entry is created : #{res.inspect}")
          else
            exit_with_error "Delegation creation failed with error #{res.inspect}"
          end
        else
          Chef::Log.info("We already have delegation on this fqdn #{response.inspect}")

          delegate_to_size = response[0]['delegate_to'].size
          if delegate_to_size != 6
            exit_with_error "Delegation entries need to be check"
          end
        end
      end
    else
      Chef::Log.info("Delegation entry will not be created for #{fqdn} with base domain #{base_domain}")
    end
  else
    exit_with_error "gslb delegation config info is not available on this inductor"
  end
end