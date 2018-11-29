# Component-specific code
# This helper contains instance variables that are used by different tests -
# add/replace/update, repair, delete
$is_windows = ENV['OS']=='Windows_NT' ? true : false

path = Pathname(__FILE__)
dir = nil
path.ascend { |f| dir = f and break if f.basename.to_s == 'volume' }
%w(util.rb raid.rb).each { |f| require File.join(dir, 'libraries', f) }

$storage,$device_map = get_storage($node)
$ciAttr = $node['workorder']['rfcCi']['ciAttributes']
$mount_point = $ciAttr['mount_point']
$mount_point = $is_windows ? "#{$mount_point[0]}:" : $mount_point.chomp('/')
