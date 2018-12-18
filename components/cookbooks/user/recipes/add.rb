require 'securerandom'

usergroup = node['user']['usergroup'] == 'true'
if usergroup
  users = JSON.parse(node['user']['usermap'])
else
  keys_string = JSON.parse(node['user']['authorized_keys']).join("\n")
  users = { node['user']['username'] => keys_string }
end
groups = JSON.parse(node[:user][:group])

unless node['platform'] =~ /windows/
  Chef::Log.info("Stopping the nslcd service")
  `sudo pkill -9  /usr/sbin/nslcd`

  # Create/delete a sudoer file for the user in /etc/sudoers.d
  # if user is sudoer - we create a file in /etc/sudoers.d, not restricting cmds
  # if not - we check allowed sudo commands
  sudoer = node['user']['sudoer'] == 'true'? true : false
  cmds = 'ALL'
  sudoer_action = :create

  # Process sudoer_cmds to find out if they're actually installed
  if !sudoer && !node['user']['sudoer_cmds'].nil? && !node['user']['sudoer_cmds'].empty?

    cmd_arr_raw = JSON.parse(node['user']['sudoer_cmds'])
    cmd_arr = []

    cmd_arr_raw.each do |cmd|
      cmd1, cmd2 = cmd.split(' ', 2)
      chk_cmd = "which #{cmd1}"
      sh = Mixlib::ShellOut.new(chk_cmd)
      result = sh.run_command
      if result.valid_exit_codes.include?(result.exitstatus)
        cmd_arr.push(result.stdout.chomp + (cmd2 ? ' ' + cmd2 : ''))
      end
      Chef::Log.info("Checking: #{chk_cmd}, result: #{result.inspect}")
    end
    cmds = cmd_arr.join(',') unless cmd_arr.empty?
  end

  # No provided sudo cmds (or they're not installed) and the user is not sudoer
  sudoer_action = :delete if (cmds == 'ALL' && !sudoer)
end


users.each do |username, keys|


if node['platform'] =~ /windows/
  home_dir = "C:/Cygwin64/home/#{username}"
  if username.include?('\\')
    home_dir = "C:/Cygwin64/home/#{username.split('\\').last.to_s}"
  end
  group_primary = 'Administrators'
else
  #Backslash in username is only allowed for Windows
  if username.include?('\\')
    msg = "Username cannot contain backslash for non-Windows platforms"
    puts "***FAULT:FATAL=#{msg}"
    Chef::Application.fatal!(msg)
  end

  if !usergroup && !node[:user][:home_directory].empty?
    home_dir = node[:user][:home_directory]
  else
    home_dir = "/home/#{username}"
  end
  group_primary = username
end

if !username.include?('\\')
  #Generate random password if needed
  password = node[:user][:password]
  if password.nil? || password.size == 0
    password = SecureRandom.urlsafe_base64(14)
  end

  user username do
    #Common attributes
    comment node[:user][:description]
    manage_home true
    home home_dir

    if node['platform'] =~ /windows/
      #Windows-specific attributes
      action :create
      password password
    else
      #Non-Windows specific attributes
      if node[:user][:system_user] == 'true'
        system true
        shell '/bin/false'
      else
        shell node[:user][:login_shell] unless node[:user][:login_shell].empty?
      end
  
      if node['etc']['passwd'][username]
        action :modify
      else
        action :create
      end
    end #if node['platform'] =~ /windows/
  end
end #if !username.include?('\\')


#Manage primary group
group "#{group_primary}-#{username}" do
  group_name group_primary
  action :create
  members [username]
  if node['platform'] =~ /windows/
    append true
  end
end

#Home and .ssh directories
if node[:user].has_key?("home_directory_mode")
  home_mode = node[:user][:home_directory_mode]
else
  home_mode = 0700
end

directory home_dir do
  owner username
  group group_primary
  mode home_mode
  if node['platform'] =~ /windows/
    rights :full_control, 'oneops'
    inherits false
  end
end

directory "#{home_dir}/.ssh" do
  owner username
  group group_primary
  mode 0700
  if node['platform'] =~ /windows/
    rights :full_control, 'oneops'
    inherits false
  end  
end

#SSH keys
file "#{home_dir}/.ssh/authorized_keys" do
  owner username
  group group_primary
  mode 0600
  content keys
  if node['platform'] =~ /windows/
    rights :full_control, 'oneops'
    inherits false
  end
end


file "/etc/sudoers.d/#{username}" do
  content "#{username} ALL = (ALL) NOPASSWD: #{cmds} \n"
  mode '0440'
  owner 'root'
  action sudoer_action
  not_if { node['platform'] =~ /windows/ }
end

# workaround for docker containers
docker = system 'test -f /.dockerinit'

if !docker
  ulimit = node[:user][:ulimit]
  if (!ulimit.nil?)
    Chef::Log.info("Setting ulimit to " + ulimit)
     `grep -E "^#{username} soft nofile" /etc/security/limits.conf`
     if $?.to_i == 0
      Chef::Log.info("ulimit already present for #{username} in the file /etc/security/limits.conf")
      `sed -i '/#{username}/d' /etc/security/limits.conf`
     end
      Chef::Log.info("adding ulimit for #{username}")
      `echo "#{username} soft nofile #{ulimit}" >> /etc/security/limits.conf`
      `echo "#{username} hard nofile #{ulimit}" >> /etc/security/limits.conf`

  else
      Chef::Log.info("ulimit attribute not found. Not writing to the limits.conf")
  end
else
  Chef::Log.info("changing limits.conf not supported on containers")
end


end #users.each do |username, keys|

#Manage secondary groups
groups.each do |g|
  group g do
    action :create
    members users.keys
  end
end
