require 'pp'
require 'excon'
require "#{COOKBOOKS_PATH}/netscaler/test/integration/netscaler_spec_utils"

netscalar_spec_utils = NetscalerSpecUtils.new($node)
netscalar_spec_utils.get_connection

conn = $node['ns_conn']
cloud_name = $node['workorder']['cloud']['ciName']

lbs = nil
if $node['workorder']['rfcCi']['ciAttributes'].has_key?('create_cloud_level_vips') &&
    $node['workorder']['rfcCi']['ciAttributes']['create_cloud_level_vips'] == "true"
  lbs = $node.loadbalancers + $node.dcloadbalancers
else
  lbs = $node.dcloadbalancers
end

lbs.each do |lb|
  sg_name = lb["sg_name"]
  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/servicegroup/#{sg_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false
  context "servicegroup" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end

  lb_name = lb["name"]
  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/lbvserver/#{lb_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false

  context "lbserver" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end

  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/lbvserver_servicegroup_binding/#{lb_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false

  context "lbserver_servicegroup" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end


  is_secondary = false
  if $node['workorder']['cloud']['ciAttributes'].has_key?('priority') &&
      $node['workorder']['cloud']['ciAttributes']['priority'].to_i != 1

    is_secondary = true

  end

  bindings = resp_obj["lbvserver_servicegroup_binding"]

  if !bindings.nil?
    !bindings.each do |sg|
      ns_sg_name = sg["servicegroupname"]

      if is_secondary
        context "service group in lbvserver" do
          it "should not exist" do
            expect(ns_sg_name).not_to eq(sg_name)
          end
        end
      else
        next if !ns_sg_name.include? cloud_name
        context "service group in lbvserver" do
          it "should exist" do
            expect(ns_sg_name).to eq(sg_name)
          end
        end
      end
    end
  end


  resp_obj = JSON.parse(conn.request(:method=>:get, :path=>"/nitro/v1/config/servicegroup_servicegroupmember_binding/#{sg_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false
  context "servicegroup servicegroupmember binding" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end

  servicegroup_servicegroupmember_binding = ""

  if  exists
    sg_members = resp_obj["servicegroup_servicegroupmember_binding"]
    servicegroup_servicegroupmember_binding += "servicegroupmembers of: #{sg_name}\n"
    servicegroup_servicegroupmember_binding += PP.pp sg_members, ""

    $node['workorder']['payLoad']['DependsOn'].each do |dep|
      if defined?(dep['ciAttributes']['public_ip'])
        ip = dep['ciAttributes']['public_ip'].to_s

        context "compute IP" do
          it "should exist" do
            expect(servicegroup_servicegroupmember_binding).to include(ip)
          end
        end

      end

    end
  end

  resp_obj = JSON.parse(conn.request(:method=>:get,
                                     :path=>"/nitro/v1/config/servicegroup_lbmonitor_binding/#{sg_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false
  context "servicegroup lbmonitor binding" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end

  if exists
    sg_monitors = resp_obj["servicegroup_lbmonitor_binding"]
    sg_monitors.each do |mon|
      mon_name = mon["monitor_name"]
      resp_obj = JSON.parse(conn.request(:method=>:get, :path=>"/nitro/v1/config/lbmonitor/#{mon_name}").body)

      exists = resp_obj["message"] =~ /Done/ ? true : false
      context "lbmonitor" do
        it "should exist" do
          expect(exists).to eq(true)
        end
      end
    end
  end

  certs = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciClassName'] =~ /Certificate/}

  if certs.size != 0
    if lb_name =~ /SSL/ && lb_name !~ /BRIDGE/

      resp_obj = JSON.parse(conn.request(
          :method=>:get,
          :path=>"/nitro/v1/config/sslvserver_sslcertkey_binding/#{lb_name}").body)

      cert_exist = resp_obj["message"] =~ /Done/ ? true : false

      context "Certificate to lbvserver" do
        it "should exist" do
          expect(cert_exist).to eq(true)
        end
      end

      cert_name = resp_obj["sslvserver_sslcertkey_binding"][0]['certkeyname']

      resp_obj = JSON.parse(conn.request(
          :method=>:get,
          :path=>"/nitro/v1/config/sslcertkey/#{cert_name}").body)

      exists = resp_obj["message"] =~ /Done/ ? true : false
      context "Certificate" do
        it "should exist" do
          expect(exists).to eq(true)
        end
      end
    end

  end


end