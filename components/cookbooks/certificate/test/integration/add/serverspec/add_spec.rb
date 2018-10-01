begin
  CIRCUIT_PATH = '/opt/oneops/inductor/circuit-oneops-1'.freeze
  require "#{CIRCUIT_PATH}/components/spec_helper.rb"
rescue Exception => e
  is_windows = ENV['OS'] == 'Windows_NT'
  CIRCUIT_PATH = "#{is_windows ? 'C:/Cygwin64' : ''}/home/oneops"
  require "#{CIRCUIT_PATH}/circuit-oneops-1/components/spec_helper.rb"
end

pem = nil
pfx = nil
key = nil
ca_cert = nil
if $node["workorder"]["payLoad"].has_key?("ManagedVia")
  cert_path = $node['workorder']['rfcCi']['ciAttributes']['path']
  ci_name = $node['workorder']['payLoad']['RealizedAs'][0]['ciName']
  cname = $node['workorder']['rfcCi']['ciAttributes']['common_name']
  pem = cert_path+"/"+ci_name+"/"+cname+".pem"
  pfx = cert_path+"/"+ci_name+"/"+cname+".pfx"
  key = cert_path+"/"+ci_name+"/"+cname+".key"
  ca_cert = cert_path+"/"+ci_name+"/ca_cert.crt"


  describe file(pem) do
    it { should be_file }
  end

  describe file(pfx) do
    it { should be_file }
  end

  describe file(key) do
    it { should be_file }
  end

  describe file(ca_cert) do
    it { should be_file }
  end

end
