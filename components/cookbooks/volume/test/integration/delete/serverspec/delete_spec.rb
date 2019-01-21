is_windows = ENV['OS']=='Windows_NT' ? true : false
$circuit_path = "#{is_windows ? 'C:/Cygwin64' : ''}/home/oneops"
require "#{$circuit_path}/circuit-oneops-1/components/spec_helper.rb"
require "#{$circuit_path}/circuit-oneops-1/components/cookbooks/volume/test/integration/volume_helper.rb"

describe file($mount_point) do
 it { should_not be_mounted }
end unless is_windows #TO-DO Check with Powershell directly, if the $mount_point is actually mounted and set online
