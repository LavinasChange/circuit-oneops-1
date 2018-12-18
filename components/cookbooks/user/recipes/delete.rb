usergroup = node['user']['usergroup'] == 'true'
if usergroup
  users = JSON.parse(node['user']['usermap'])
else
  keys_string = JSON.parse(node['user']['authorized_keys']).join("\n")
  users = { node['user']['username'] => keys_string }
end
group = JSON.parse(node['user']['group'])
is_windows = node['platform'] =~ /windows/
group.push('Administrators') if is_windows && !group.include?('Administrators')

if !is_windows
  Chef::Log.info("Stopping the nslcd service")
  `sudo pkill -9  /usr/sbin/nslcd`
end


users.each do |username, keys|

if username != "root" && !is_windows
  execute "pkill -9 -u #{username} ; true"
end

user username do
  action :remove
end

group username do
  action :remove
  not_if {is_windows}
end

#in windows remove the user from its groups
group.each do |g|
  group g do
    excluded_members username
    append true
    action :manage
  end
end if is_windows

end
