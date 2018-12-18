name             "User"
description      "User"
version          "0.1"
maintainer       "OneOps"
maintainer_email "support@oneops.com"
license          "Apache License, Version 2.0"

grouping 'default',
  :access => "global",
  :packages => [ 'base', 'mgmt.catalog', 'mgmt.manifest', 'catalog', 'manifest', 'bom' ]

attribute 'usergroup',
  :description => 'Combine users in a group',
  :default => 'false',
  :format => {
    :help => 'Create multiple users',
    :editable => false,
    :category => '1.Global',
    :order => 1,
    :form => { 'field' => 'checkbox' }
  }

attribute 'username',
  :description => "Username",
  :format => {
    :important => true,
    :help => 'Username',
    :category => '1.Global',
    :editable => false,
    :order => 2,
    :pattern => "(^[a-z][a-z0-9_-]{1,60}\\\\|^)[a-z0-9_-]{3,15}$",
    :filter   => { 'all' => { 'visible' => 'usergroup:neq:true' } }
  }

attribute 'ulimit',
  :description => "Max Open Files",
  :required => "required",
  :default => '16384',
  :format => {
    :help => 'Ulimit value for number of max open files. Should be even multiple of 1024',
    :category => '1.Global',
    :order => 6,
    :pattern => '^[0-9]{4,6}$'
  }

attribute 'description',
  :description => "Description",
  :format => {
    :help => 'Enter description for this user',
    :category => '1.Global',
    :order => 3
  }

attribute 'home_directory',
  :description => "Home Directory",
  :format => {
    :help => 'Specify custom directory or leave empty for the system default, usually /home',
    :category => '1.Global',
    :order => 4,
    :filter   => { 'all' => { 'visible' => 'usergroup:neq:true' } }
  }

attribute 'home_directory_mode',
  :description => "Home Directory Mode",
  :default => '755',
  :format => {
    :help => 'Specify the directory mode/priv in unix format. e.g. 755 or 700',
    :category => '1.Global',
    :order => 5
  }

attribute 'login_shell',
  :description => "Login shell",
  :default => '/bin/bash',
  :format => {
    :help => 'Default login shell for the user',
    :category => '1.Global',
    :order => 5
  }

attribute 'system_account',
  :description => "System Account",
  :default => 'true',
  :format => {
    :help => 'System Account users will be created with no aging information in /etc/shadow, and their numeric identifiers are chosen in the SYS_UID_MIN-SYS_UID_MAX range, defined in /etc/login.defs, instead of UID_MIN-UID_MAX (and their GID counterparts for the creation of groups).',
    :category => '2.Options',
    :order => 1,
    :form => { 'field' => 'checkbox' }
  }

attribute 'sudoer',
  :description => "Enable Sudo Access",
  :default => 'true',
  :format => {
    :help => 'Enable sudo access for this user to enable administrative priviledges',
    :category => '2.Options',
    :order => 2,
    :form => { 'field' => 'checkbox' }
  }

  attribute 'group',
    :description => "Secondary Groups",
    :data_type => 'array',
    :default => '[]',
    :format => {
      :help => 'Enter a list of Secondary Groups for this user',
      :category => '2.Options',
      :order => 3
    }

attribute 'sudoer_cmds',
  :description => 'Commands for sudo',
  :data_type => 'array',
  :default => '["tcpdump", "jmap", "jcmd", "jstat", "jstack", "strace", "service", "chmod a+r /tmp/heapdump*.prof"]',
  :format => {
    :help => 'Enter a list of commands allowed to be executed with sudo',
    :category => '2.Options',
    :order => 4,
    :filter => {'all' => {'visible' => 'false', 'editable' => 'false'}}
  }

attribute 'authorized_keys',
  :description => "Authorized Keys",
  :data_type => 'array',
  :default => '[]',
  :format => {
    :help => 'Enter a list of public keys to authorize SSH key access to this account',
    :category => '3.Access',
    :order => 1,
    :filter   => { 'all' => { 'visible' => 'usergroup:neq:true' } }
  }
  
attribute 'password',
  :description => "Password (currently Windows only)",
  :encrypted => true,
  :format => {
    :help => 'Applies to Windows VMs only, if left blank a random password will be generated',
    :category => '3.Access',
    :order => 2,
    :filter   => { 'all' => { 'visible' => 'usergroup:neq:true' } }
  }

attribute 'usermap',
  :description => 'Usernames and SSH keys map',
  :default => '{}',
  :data_type => 'hash',
  :format => {
    :help => 'Map of usernames and ssh keys, in form of "username" => "SSH key"',
    :category => '3.Access',
    :order => 3,
    :filter   => { 'all' => { 'visible' => 'usergroup:eq:true' } }
  }

recipe "repair", "Repair User"
