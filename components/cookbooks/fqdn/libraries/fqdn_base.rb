# A base/util module for fqdn.
#
# Cookbook Name:: fqdn
# Library:: fqdn_base
#
# Author : OneOps
# Apache License, Version 2.0
require 'resolv'
require 'ipaddr'

def get_ostype

  ostype = 'linux'
  os = node[:workorder][:payLoad][:DependsOn].select {|d| (d.ciClassName.split('.').last == 'Os')}
  if node[:workorder][:payLoad].has_key?('os_payload') && node[:workorder][:payLoad][:os_payload].first[:ciAttributes][:ostype] =~ /windows/
    ostype = 'windows'
  elsif !os.empty? && os.first[:ciAttributes][:ostype] =~ /windows/
    ostype = 'windows'
  end

  return ostype
end #def get_ostype

def get_dns_service
  cloud_name = node[:workorder][:cloud][:ciName]
  service_attrs = node[:workorder][:services][:dns][cloud_name][:ciAttributes]

  #Find zone subservices satisfying the criteria
  zone_services = []
  node[:workorder][:services][:dns].each do |s|
 
    if s.first =~ /#{cloud_name}\// && s.last[:ciAttributes].has_key?('criteria_type')

      #platform check
      if s.last[:ciAttributes][:criteria_type] == 'platform' && get_ostype == s.last[:ciAttributes][:criteria_value]
        zone_services.push(s.last)
      end
    end
  end

  if zone_services.uniq.size > 1
    Chef::Log.warn("Multiple zone subservices with satisfying criteria have been found. Using the default service...")
  end

  #One and only one satisfying zone subservice is found - use it instead of default dns service
  if zone_services.uniq.size == 1
    service_attrs = zone_services.first[:ciAttributes]
  end

  return service_attrs
end #def get_dns_service

def get_windows_domain_service
  cloud_name = node[:workorder][:cloud][:ciName]
  windows_domain = nil
  if node[:workorder][:payLoad].has_key?('windowsdomain')
    windows_domain = node[:workorder][:payLoad][:windowsdomain].first
  elsif node[:workorder][:services].has_key?('windows-domain')
    windows_domain = node[:workorder][:services]['windows-domain'][cloud_name]
  end
  return windows_domain
end #def get_windows_domain_service

def is_windows
  return ( get_ostype == 'windows' && get_windows_domain_service )
end #def is_windows

def get_windows_domain

  if get_dns_service[:zone].split('.').last(2) == get_windows_domain_service[:ciAttributes][:domain].split('.').last(2)
    return get_windows_domain_service[:ciAttributes][:domain].downcase
  else
    return get_dns_service[:zone].downcase
  end

end #def get_windows_domain

def get_customer_domain
  #environment.assembly.cloud_id.zone
  if is_windows
    arr = [node[:workorder][:payLoad][:Environment][0][:ciName], node[:workorder][:payLoad][:Assembly][0][:ciName], get_dns_service[:cloud_dns_id], get_windows_domain]
    customer_domain = '.' + arr.join('.').downcase
  else
    customer_domain = node[:customer_domain].downcase
  end

  if customer_domain !~ /^\./
    customer_domain = '.' + customer_domain
  end
  return customer_domain
end #def get_customer_domain

def is_wildcard_enabled(node)
  if node['workorder'].has_key?('config') && !node['workorder']['config'].empty?
    config = node['workorder']['config']
    if config.has_key?('is_wildcard_enabled') && !config['is_wildcard_enabled'].empty? && config['is_wildcard_enabled'] == 'true'
      return true
    else
      return false
    end
  end
  return false
end




module Fqdn

  module Base

    require 'json'
    require 'uri'
    include Chef::Mixin::ShellOut
    
    
    def is_hijackable (dns_name,ns)
      is_hijackable = false
      cmd = "dig +short TXT txt-#{dns_name} @#{ns}"  
      Chef::Log.info(cmd)
      vals = `#{cmd}`.split("\n")
      vals.each do |val|
        # check that hijack is set from a different domain
        is_hijackable = true if val.include?("hijackable") && !val.include?(node.customer_domain)
      end

      Chef::Log.info("is_hijackable: #{is_hijackable}")
      return is_hijackable
    end
    
    
    def get_existing_dns (dns_name,ns)
      existing_dns = Array.new
      if dns_name =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
        ptr_name = $4 +'.' + $3 + '.' + $2 + '.' + $1 + '.in-addr.arpa'
        cmd = "dig +short PTR #{ptr_name} @#{ns}"
        Chef::Log.info(cmd)
        existing_dns += `#{cmd}`.split("\n").map! { |v| v.gsub(/\.$/,"") }
      elsif dns_name =~ Resolv::IPv6::Regex ###check this !!
        ptr_name= IPAddr.new(dns_name).reverse
        cmd = "dig +short PTR #{ptr_name} @#{ns}"
        Chef::Log.info(cmd)
        existing_dns += `#{cmd}`.split("\n").map! { |v| v.gsub(/\.$/,"") }
      else
        ["A", "AAAA", "CNAME"].each do |record_type|
          Chef::Log.info("dig +short #{record_type} #{dns_name} @#{ns}")
          vals = `dig +short #{record_type} #{dns_name} @#{ns}`.split("\n").map! { |v| v.gsub(/\.$/,"") }
          # skip dig's lenient A record lookup thru CNAME
          next if (record_type == "A" && vals.size > 1 && vals[0] !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) || (record_type == "AAAA" && vals.size > 1 && vals[0] !~ Resolv::IPv6::Regex
          )
          existing_dns += vals

        end
      end
      Chef::Log.info("existing: "+existing_dns.sort.inspect)
      return existing_dns
    end    

    
    # get dns record type - check for ip addresses
    def get_record_type (dns_name, dns_values)
      record_type = "cname"
      ips = dns_values.grep(/\d+\.\d+\.\d+\.\d+/)
      dns_values.each do |dns_value|
        if dns_value =~ Resolv::IPv6::Regex
          record_type = "aaaa"
        end
      end


      if ips.size > 0
        record_type = "a"
      end
      if dns_name =~ /^\d+\.\d+\.\d+\.\d+$/ || dns_name =~ Resolv::IPv6::Regex
        record_type = "ptr"
      end
      if dns_name =~ /^txt-/
        record_type = "txt"
      end
      return record_type
    end
    
    
    def get_provider
      cloud_name = node[:workorder][:cloud][:ciName]
      provider_service = node[:workorder][:services][:dns][cloud_name][:ciClassName].split(".").last.downcase
      provider = "fog"
      if provider_service =~ /infoblox|azuredns|designate|ddns/
        provider = provider_service
      end
      Chef::Log.debug("Provider is: #{provider}")  
      return provider
    end

    def fail_with_fault(msg)
      puts "***FAULT:FATAL=#{msg}"
      Chef::Application.fatal!(msg)
    end

    # get dns value using dns_record attr or if empty resort to case stmt based on component class
    def get_dns_values (components)
      values = Array.new
      components.each do |component|
    
        attrs = component[:ciAttributes]
    
        dns_record = attrs[:dns_record] || ''
    
        # backwards compliance: until all computes,lbs,clusters have dns_record populated need to get via case stmt
        if dns_record.empty?
          case component[:ciClassName]
          when /Compute/
            if attrs.has_key?("public_dns") && !attrs[:public_dns].empty?
             dns_record = attrs[:public_dns]+'.'
            else
             dns_record = attrs[:public_ip]
            end
    
            if location == ".int" || dns_entry == nil || dns_entry.empty?
              dns_record = attrs[:private_ip]
            end
    
          when /Lb/
            dns_record = attrs[:dns_record]
          when /Cluster/
            dns_record = attrs[:shared_ip]
          end
        else
          # dns_record must be all lowercase
          dns_record.downcase!
          # unless ends w/ . or is an ip address
          dns_record += '.' unless dns_record =~ /,|\.$|^\d+\.\d+\.\d+\.\d+$/ || dns_record =~ Resolv::IPv6::Regex
        end
    
        if dns_record.empty?
          Chef::Log.error("cannot get dns_record value for: "+component.inspect)
          exit 1
        end
    
        if dns_record =~ /,/
          values.concat dns_record.split(",")
        else
          values.push(dns_record)
        end
      end
      return values
    end

    def get_record_hash(dns_name, dns_value, dns_type)
      record = { :name => dns_name.downcase }
      case dns_type
      when 'cname'
        record['canonical'] = dns_value
      when 'a'
        record['ipv4addr'] = dns_value
      when 'aaaa'
        record['ipv6addr'] = dns_value
      when 'ptr'
        if dns_name =~ Resolv::IPv4::Regex
          record = { 'ipv4addr' => dns_name, 'ptrdname' => dns_value }
        elsif dns_name =~ Resolv::IPv6::Regex
          record = { 'ipv6addr' => dns_name, 'ptrdname' => dns_value }
        end
      when 'txt'
        record = { 'name' => dns_name, 'text' => dns_value }
      end
      record
    end

    def check_record(dns_name, dns_value)
      res = node.infoblox_conn.request(:method => :get, :path => '/wapi/v1.0/network')

      exit_with_error "Infoblox Connection Unsuccessful. Response: #{res.inspect}" if res.status != 200

      Chef::Log.info('Infoblox Connection Successful.')

      api_version = 'v1.0'
      api_version = 'v1.2' if dns_name =~ Resolv::IPv6::Regex # ipv6addr attribute is recognized only in infoblox api version >= 1.1

      dns_val = dns_value.is_a?(String) ? [dns_value] : dns_value
      dns_type = get_record_type(dns_name, dns_val)
      record_hash = get_record_hash(dns_name, dns_value, dns_type)

      records = JSON.parse(node.infoblox_conn.request(:method => :get, :path => "/wapi/#{api_version}/record:#{dns_type}", :body => JSON.dump(record_hash)).body)

      if records.size.zero?
        Chef::Log.info('check_record: DNS Record Entry Already Deleted.')
        return false
      else
        Chef::Log.info('check_record: DNS Record Entry is Available.')
        return true
      end
    end

    def verify(dns_name, dns_values, ns, max_retry_count=30)
      if dns_values.count > max_retry_count
        max_retry_count = dns_values.count + 1
      end

      retry_count = 0
      dns_type = get_record_type(dns_name, dns_values)
  
      dns_values.each do |dns_value|
        if dns_value[-1,1] == '.'
          dns_value.chomp!('.')
        end
        
        verified = false
        provider = get_provider
        while !verified && retry_count<max_retry_count do
          if provider =~ /infoblox/
            verified = check_record(dns_name, dns_value)
          else
            dns_lookup_name = dns_name
            if dns_name =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
              dns_lookup_name = $4 +'.' + $3 + '.' + $2 + '.' + $1 + '.in-addr.arpa'
            elsif dns_name =~ Resolv::IPv6::Regex
              dns_lookup_name = IPAddr.new(dns_name).reverse
            end
            puts "dig +short #{dns_type} #{dns_lookup_name} @#{ns}"
            existing_dns = `dig +short #{dns_type} #{dns_lookup_name} @#{ns}`.split('\n').map! { |v| v.gsub(/\.$/, '') }
            Chef::Log.info("verify #{dns_name} has: " + dns_value)
            Chef::Log.info("ns #{ns} has: " + existing_dns.sort.to_s)
            verified = false
            existing_dns.each do |val|
              if val.downcase.include? dns_value
                verified = true
                Chef::Log.info('verified.')
              end
            end
          end

          if !verified && max_retry_count > 1
            Chef::Log.info("waiting 10sec for #{ns} to get updated...")
            sleep 10
          end
          retry_count +=1
        end
        if !verified
          return false
        end       
      end
      Chef::Log.info("DNS Record with Name: #{dns_name} Verified.")
      return true
    end


    def ddns_execute(cmd_stmt)
      
      Chef::Log.info("cmd: #{cmd_stmt}")
      cmd_content = node.ddns_header + #{cmd_stmt}\nsend\n"
      cmd_file = node.ddns_key_file + '-cmd'
      File.open(cmd_file, 'w') { |file| file.write(cmd_content) }
      cmd = "nsupdate -k #{node.ddns_key_file} #{cmd_file}"
      puts cmd
      result = `#{cmd}`      
      if $?.to_i != 0 || result =~ /error/i
        fail_with_fault result
      end
      
    end

    def is_last_active_cloud_in_dc
      cloud_name = node[:workorder][:cloud][:ciName]
      # skip deletes if other active clouds for same dc
      if node[:workorder][:services].has_key?("gdns")
        cloud_service =  node[:workorder][:services][:gdns][cloud_name]
      end
      if node.workorder.rfcCi.rfcAction == "delete"
        lbs = node.workorder.payLoad.DependsOn.select { |d| d[:ciClassName] =~ /Lb/}
        if !(lbs.nil? || lbs.size==0)
          lb = lbs.first
          JSON.parse(lb[:ciAttributes][:vnames]).keys.each do |lb_name|
            return true if lb_name.split('.')[4] =~ /cdc5|cdc6|cdc7|cdc8/
          end
        end
      end
      if node.workorder.box.ciAttributes.has_key?("is_platform_enabled") &&
          node.workorder.box.ciAttributes.is_platform_enabled == 'true' &&
          node.workorder.payLoad.has_key?("activeclouds") && !cloud_service.nil?
        node.workorder.payLoad["activeclouds"].each do |service|

          if service[:ciAttributes].has_key?("gslb_site_dns_id") &&
              service[:nsPath] != cloud_service[:nsPath] &&
              service[:ciAttributes][:gslb_site_dns_id] == cloud_service[:ciAttributes][:gslb_site_dns_id]

            Chef::Log.info("not last active cloud in DC. #{service[:nsPath].split("/").last}")
            return false
          end
        end
        return true
      end
      return true
    end

    def is_last_active_cloud
      cloud_name = node[:workorder][:cloud][:ciName]
      # skip deletes if other active clouds for same dc
      if node[:workorder][:services].has_key?("gdns")
        cloud_service =  node[:workorder][:services][:gdns][cloud_name]
      end
      if node.workorder.box.ciAttributes.has_key?("is_platform_enabled") &&
          node.workorder.box.ciAttributes.is_platform_enabled == 'true' &&
          node.workorder.payLoad.has_key?("activeclouds") && !cloud_service.nil?
        node.workorder.payLoad["activeclouds"].each do |service|

          if service[:nsPath] != cloud_service[:nsPath]
            Chef::Log.info("not last active cloud: #{service[:nsPath].split("/").last}")
            return false
          end
        end
        return true
      end
      return true
    end

  end
end
