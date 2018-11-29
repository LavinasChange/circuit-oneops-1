# This file runs tests for add/update/replace actions

require 'pathname'
path = Pathname(__FILE__)
dir = path.dirname
dir2 = nil
path.ascend { |f| dir2 = f and break if f.basename.to_s == 'components' }
require File.join(dir2, 'spec_helper.rb')
require File.join(dir, 'volume_helper.rb')

#Run generic tests
describe file($mount_point) do
  it { should be_directory }
end

#Run platform specific tests
cloud_name = $node['workorder']['cloud']['ciName']
if $node['workorder']['services'].key?('compute')
  provider = $node['workorder']['services']['compute'][cloud_name]['ciClassName'].split('.').last.downcase
end

if $storage.nil? && provider =~ /azure/ && $ciAttr['skip_vol'] == 'true'
  require File.join(dir, 'place_on_root_spec.rb')
elsif $is_windows
  require File.join(dir, 'windows_spec.rb')
else
  require File.join(dir, 'default_spec.rb')
end
