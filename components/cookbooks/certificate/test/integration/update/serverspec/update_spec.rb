require 'spec_helper'

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
end

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
