require 'resolv'
require 'ipaddr'
require 'excon'

is_windows = ENV['OS'] == 'Windows_NT'

begin
  CIRCUIT_PATH = '/opt/oneops/inductor/circuit-oneops-1'
  COOKBOOKS_PATH = "#{CIRCUIT_PATH}/components/cookbooks".freeze
  require "#{CIRCUIT_PATH}/components/spec_helper.rb"
  require "#{COOKBOOKS_PATH}/fqdn/test/integration/library.rb"
rescue Exception =>e
  CIRCUIT_PATH = "#{is_windows ? 'C:/Cygwin64' : ''}/home/oneops"
  require "#{CIRCUIT_PATH}/circuit-oneops-1/components/spec_helper.rb"
  require "/home/oneops/circuit-oneops-1/components/cookbooks/fqdn/test/integration/library.rb"
end

lib = Library.new
entries = lib.build_entry_list
entries.each do |entry|
  dns_name = entry['name']
  dns_value = entry['values']
  dns_val = dns_value.is_a?(String) ? [dns_value] : dns_value

  if !dns_val.nil? && dns_val.size != 0
    dns_val.each do |value|
      flag = lib.check_record(dns_name, value)
      context "FQDN mapping" do
        it "should be available" do
          expect(flag).to eq(false)
        end
      end
    end
  end
end

cloud_name = $node['workorder']['cloud']['ciName']

depends_on_lb = false
$node['workorder']['payLoad']['DependsOn'].each do |dep|
  depends_on_lb = true if dep['ciClassName'] =~ /Lb/
end

env = $node['workorder']['payLoad']['Environment'][0]['ciAttributes']

gdns_service = nil
if $node['workorder']['services'].has_key?('gdns') &&
    $node['workorder']['services']['gdns'].has_key?(cloud_name)
  gdns_service = $node['workorder']['services']['gdns'][cloud_name]
end

if env.has_key?("global_dns") && env["global_dns"] == "true" && depends_on_lb &&
    !gdns_service.nil? && gdns_service["ciAttributes"]["gslb_authoritative_servers"] != '[]'

  cloud_service= nil
  cloud_name = $node['workorder']['cloud']['ciName']
  if $node['workorder']['services'].has_key?('lb')
    cloud_service = $node['workorder']['services']['lb'][cloud_name]['ciAttributes']
  else
    cloud_service = $node['workorder']['services']['gdns'][cloud_name]['ciAttributes']
  end


  host = $node['workorder']['services']['gdns'][cloud_name]['ciAttributes']['host']
  ci = $node['workorder']['box']
  gslb_service_name = lib.get_gslb_service_name
  conn = lib.gen_conn(cloud_service,host)

  resp_obj = JSON.parse(conn.request(
      :method => :get,
      :path => "/nitro/v1/config/gslbservice/#{gslb_service_name}").body)

  if resp_obj["message"] =~ /The GSLB service does not exist/

    gslb_service_name = lib.get_gslb_service_name_by_platform

    resp_obj = JSON.parse(conn.request(
        :method=>:get,
        :path=>"/nitro/v1/config/gslbservice/#{gslb_service_name}").body)

  end

  if $node['workorder']['cloud']['ciAttributes']['priority'] == "1"
    context "GSLB service" do
      it "should exist" do
        status = resp_obj["message"]
        expect(status).to eq("Done")
      end
    end
  end

  lbs = []
  JSON.parse($node['workorder']['rfcCi']['ciAttributes']['gslb_vnames']).keys.each do |lb_name|
    lbs.push({:name => lb_name})
  end

  lbs.each do |lb|
    resp_obj = JSON.parse(conn.request(
        :method=>:get,
        :path=>"/nitro/v1/config/gslbvserver_gslbservice_binding/#{lb[:name]}").body)
    services = lib.get_all_gslb_service

    service_names = Array.new
    resp_obj["gslbvserver_gslbservice_binding"].each do |s|
      service_names.push(s["servicename"])
    end

    services.each do |name|
      resp = JSON.parse(conn.request(
          :method=>:get,
          :path=>"/nitro/v1/config/gslbservice/#{name}").body)

      puts service_names
      if resp["message"] =~ /Done/
        context "GSLB service to gslbvserver" do
          it "should exist" do
            status = service_names.include? name
            expect(status).to eq(true)
          end
        end
      end
    end

  end


  if $node['workorder'].has_key?('config') && $node['workorder']['config'].has_key?('delegation_enable') && $node['workorder']['config']['delegation_enable'].to_s.downcase == "true"

    api_version = "v2.5"
    platform_name = $node['workorder']['box']['ciName']
    cloud_name = $node['workorder']['cloud']['ciName']
    gdns = $node['workorder']['services']['gdns'][cloud_name]['ciAttributes']
    base_domain = gdns['gslb_base_domain']

    subdomain = $node['workorder']['payLoad']['Environment'][0]['ciAttributes']['subdomain']

    gslb_domain = [platform_name, subdomain, base_domain].join(".")
    if subdomain.empty?
      gslb_domain = [platform_name, base_domain].join(".")
    end
    fqdn = gslb_domain.downcase

    record_query = {
        "fqdn" => fqdn
    }

    delegation_info = "/secrets/gslb_delegation.json"
    describe file(delegation_info) do
      it { should be_file }
    end

    data_json = JSON.parse(File.read(delegation_info))

    delegation_entry_flag = false

    data_json["delegation"].each do |record|
      if record["base_domain"] == base_domain

        if record.has_key?("excluded_domains") && record["excluded_domains"].size != 0
          valid_domain = true
          excluded_domains = record["excluded_domains"]

          excluded_domains.each do |domain|
            if fqdn.end_with?(domain)
              valid_domain = false
              break
            end
          end

          if valid_domain
            delegation_entry_flag = true
          end
          break
        end
      end
    end

    if delegation_entry_flag
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

      ENV['http_proxy'] = http_proxy
      ENV['https_proxy'] = https_proxy

      response = JSON.parse(conn.request(
          :method => :get,
          :path => "/wapi/#{api_version}/zone_delegated",
          :body => JSON.dump(record_query)).body)


      context "Delegated record entry" do
        it "should exist" do
          expect(response.size).not_to eq(0)
        end
      end

      delegate_to_size = response[0]['delegate_to'].size
      context "Delegated rule" do
        it "should exist" do
          expect(delegate_to_size).to eq(6)
        end
      end
    end

  end

end

