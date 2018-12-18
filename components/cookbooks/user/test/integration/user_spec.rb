is_windows = ENV['OS']=='Windows_NT' ? true : false
$circuit_path = "#{is_windows ? 'C:/Cygwin64' : ''}/home/oneops"
require "#{$circuit_path}/circuit-oneops-1/components/spec_helper.rb"

usergroup = $node['user']['usergroup'] == 'true'
if usergroup
  users = JSON.parse($node['user']['usermap'])
else
  keys_string = JSON.parse($node['user']['authorized_keys']).join("\n")
  users = { $node['user']['username'] => keys_string }
end

group = JSON.parse($node['user']['group'])

users.each do |username, keys|
  user = username.gsub('\\','\\\\\\')
  if !usergroup && !$node['user']['home_directory'].empty?
    home_dir = $node['user']['home_directory']
  else
    home_dir = "/home/#{username}"
  end

  if is_windows
    group.push('Administrators') unless group.include?('Administrators')
    group.each do |g|
      describe command("& {net localgroup #{g} } | select-string -pattern '^#{user}$'") do
        its(:stdout) { should_not be_empty  }
      end
    end
  else
    describe user(user) do
      it { should exist }
      it { should have_login_shell $node['user']['login_shell'] }
      it { should have_home_directory "#{home_dir}" }
    end

    group.each do |g|
      describe user(user) do
        it { should belong_to_group g }
      end
    end
  end
end #users.each do |username, keys|
