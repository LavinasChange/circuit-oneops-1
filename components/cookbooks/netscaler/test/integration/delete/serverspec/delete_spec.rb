require 'pp'
require 'excon'
require "#{COOKBOOKS_PATH}/netscaler/test/integration/netscaler_spec_utils"

netscalar_spec_utils = NetscalerSpecUtils.new($node)
netscalar_spec_utils.get_connection

conn = $node['ns_conn']
cloud_name = $node['workorder']['cloud']['ciName']

lbs = $node.loadbalancers + $node.dcloadbalancers

lbs.each do |lb|
  sg_name = lb["sg_name"]
  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/servicegroup/#{sg_name}").body)

  exists = resp_obj["message"] =~ /No such resource/ ? true : false
  context "servicegroup" do
    it "should not exist" do
      expect(exists).to eq(true)
    end
  end

  lb_name = lb["name"]
  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/lbvserver_servicegroup_binding/#{lb_name}").body)


  exists  = resp_obj["message"] =~ /No such resource/ ? true : false
  context "servicegroup to lbserver binding" do
    it "should not exist" do
      expect(exists).to eq(true)
    end
  end

  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/lbvserver/#{lb_name}").body)

  exists = resp_obj["message"] =~ /No such resource/ ? true : false

  context "lbserver" do
    it "should not exist" do
      expect(exists).to eq(true)
    end
  end

  certs = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciClassName'] =~ /Certificate/}

  if certs.size != 0 && lb_name =~ /SSL/ && lb_name !~ /BRIDGE/

    resp_obj = JSON.parse(conn.request(
        :method=>:get,
        :path=>"/nitro/v1/config/sslvserver_sslcertkey_binding/#{lb_name}").body)

    exists = resp_obj["message"] =~ /No such resource/ ? true : false

    context "Certificate binding" do
      it "should exist" do
        expect(exists).to eq(true)
      end
    end

  end

end