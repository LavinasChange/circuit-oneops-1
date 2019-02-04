include_pack 'genericlb'

name         'esplus_master'
description  'Strati Search Elasticsearch'
type         'Platform'
category     'Search Engine'


platform :attributes => {
    "autoreplace" => "true",
    "replace_after_minutes" => 60,
    "replace_after_repairs" => 3
}

environment "single", {}
environment "redundant", {}

# Overriding the default compute
resource 'compute',
   :cookbook => 'oneops.1.compute',
   :attributes => {'size' => 'M'}

resource "os",
   :cookbook => "oneops.1.os",
   :attributes => {
       'limits' => '{ "nofile" : "200000", "nproc"  : "65536", "memlock" : "unlimited", "as" : "unlimited" }',
       'sysctl' => '{"vm.max_map_count":"131072", "net.ipv4.tcp_mem":"1529280 2039040 3058560", "net.ipv4.udp_mem":"1529280 2039040 3058560", "fs.file-max":"1611021"}'
   }

resource 'user-app',
   :cookbook => 'oneops.1.user',
   :design => true,
   :requires => {'constraint' => '1..1'},
   :attributes => {
       'username' => 'app',
       'description' => 'App-User',
       'home_directory' => '/app/',
       'system_account' => true,
       'sudoer' => true,
       'ulimit' => '200000'
   }

# overwrite volume and filesystem from generic_ring with new mount point
resource 'volume-app',
   :cookbook => "oneops.1.volume",
   :requires => {'constraint' => '1..1', 'services' => 'compute'},
   :attributes => {'mount_point' => '/app/',
                   'size' => '100%FREE',
                   'device' => '',
                   'fstype' => 'ext4',
                   'options' => ''
   }

# the storage component is for Cinder (or the equivalent in Azure or other cloud providers) - persistent block storage
# Storage component is added to the base pack already. We are just overriding the default values of attributes here
resource "storage",
   :cookbook => "oneops.1.storage",
   :design => true,
   :attributes => {"size" => '10G', "slice_count" => '1'},
   :requires => {"constraint" => "0..1", "services" => "storage"}

# the volume component is for Cinder (or the equivalent in Azure or other cloud providers) - persistent block storage
resource "volume-blockstorage",
   :cookbook => "oneops.1.volume",
   :design => true,
   :requires => {"constraint" => "0..1", "services" => "compute,storage"},
   # Mount point - The mount point to host the cinder blockstorage
   # size - percentage of free disk space
   # fstype - file system type created for the Linux machines
   :attributes => {
       :mount_point => '/app',
       :size => '100%FREE',
       :device => '',
       :fstype => 'ext4',
       :options => ''
   },
   :monitors => {
       'usage' => {
           'description' => 'Usage',
           'chart' => {'min' => 0, 'unit' => 'Percent used'},
           'cmd' => 'check_disk_use!:::node.workorder.rfcCi.ciAttributes.mount_point:::',
           'cmd_line' => '/opt/nagios/libexec/check_disk_use.sh $ARG1$',
           'metrics' => {
               'space_used' => metric(:unit => '%', :description => 'Disk Space Percent Used'),
               'inode_used' => metric(:unit => '%', :description => 'Disk Inode Percent Used')
           },
           :thresholds => {
               'LowDiskSpace' => threshold('1m', 'avg', 'space_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1)),
               'LowDiskInode' => threshold('1m', 'avg', 'inode_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1))
           }
       }
   }

resource "java",
   :cookbook => "oneops.1.java",
   :design => true,
   :requires => {
       :constraint => "1..1",
       :services => '*mirror',
       :help => "Java Programming Language Environment"
   },
   :attributes => {
       :jrejdk => "jdk",
       :version => "8",
       :sysdefault => "true",
       :flavor => "oracle"
   }


resource 'elasticsearch-master',
   :cookbook => 'oneops.1.es6plus',
   :design => true,
   :requires => {'constraint' => '1..*', 'services' => 'mirror'},
   :attributes => {
       'version' => '6.6.0',
       'data' => 'false',
       'master' => 'true',
       'memory' => '1g'
   }


resource "secgroup",
   :cookbook => "oneops.1.secgroup",
   :design => true,
   :attributes => {
       "inbound" => '[
    "22 22 tcp 0.0.0.0/0",
    "9200 9400 tcp 0.0.0.0/0",
    "13001 13001 tcp 0.0.0.0/0"
  ]'
   },
   :requires => {
       :constraint => "1..1",
       :services => "compute"
   }


resource "hostname",
   :cookbook => "oneops.1.fqdn",
   :design => true,
   :requires => {
       :constraint => "1..1",
       :services => "dns",
       :help => "optional hostname dns entry"
   },
   # enable ptr and change ptr_source to 'instance'
   :attributes => {
       :ptr_enabled => "true",
       :ptr_source => "instance"
   }


# depends_on
[
    {:from => 'user-app', :to => 'os'},
    {:from => 'user-app', :to => 'volume-app'},
    {:from => 'java', :to => 'os'},
    {:from => 'java', :to => 'compute'},
    {:from => 'elasticsearch-master', :to => 'user-app'},
    {:from => 'volume-app', :to => 'os'},
    {:from => 'volume-app', :to => 'compute'},
    {:from => 'hostname', :to => 'os'},
    {:from => 'user-app', :to => 'volume-blockstorage'},
    {:from => 'elasticsearch-master', :to => 'volume-app'}, # solrcloud need access to mount point from volume-app
    {:from => 'elasticsearch-master', :to => 'volume-blockstorage'},
    {:from => 'volume-blockstorage', :to => 'storage'},
    {:from => 'storage', :to => 'compute'},
    {:from => 'storage', :to => 'os'},
    {:from => 'user-app',      :to => 'compute'},
    {:from => 'volume-blockstorage',  :to => 'compute'},
    {:from => 'elasticsearch-master', :to => 'java'  },
    {:from => 'elasticsearch-master', :to => 'hostname'}].each do |link|
  relation "#{link[:from]}::depends_on::#{link[:to]}",
           :relation_name => 'DependsOn',
           :from_resource => link[:from],
           :to_resource => link[:to],
           :attributes => {"flex" => false, "min" => 1, "max" => 1}
end

# propagation rule for replace
[ 'hostname' ].each do |from|
  relation "#{from}::depends_on::compute",
           :relation_name => 'DependsOn',
           :from_resource => from,
           :to_resource   => 'compute',
           :attributes    => { "propagate_to" => 'from', "flex" => false, "min" => 1, "max" => 1 }
end

# managed_via
['elasticsearch-master', 'user-app', 'java', 'volume-app', 'storage', 'volume-blockstorage'].each do |from|
  relation "#{from}::managed_via::compute",
           :except => ['_default'],
           :relation_name => 'ManagedVia',
           :from_resource => from,
           :to_resource => 'compute',
           :attributes => {}
end