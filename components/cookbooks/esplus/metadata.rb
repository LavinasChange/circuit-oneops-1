name              "esplus"
description       "Installs/Configures ElasticSearch With LB"
version           "1.0"
maintainer        "Strati-AF Search Team"
maintainer_email  "strati-af-search@email.wal-mart.com"
license           "Copyright Strati-AF Search Team, All rights reserved."

depends "ark"

grouping 'default',
         :access => "global",
         :packages => ['base', 'mgmt.catalog', 'mgmt.manifest', 'catalog', 'manifest', 'bom']

attribute 'version',
  :description => 'Version',
  :required => 'required',
  :default => '6.6.0',
  :format => {
      :important => true,
      :help => 'Version of ElasticSearch',
      :category => '1.Cluster',
      :order => 1,
      :form => {'field' => 'select', 'options_for_select' => [['6.6.0', '6.6.0']]}
  }

attribute 'cluster_name',
  :description => 'Cluster Name',
  :default => 'elasticsearch',
  :format => {
      :help => 'Name of the elastic search cluster',
      :category => '1.Cluster',
      :important => true,
      :order => 2
  }

attribute 'custom_elasticsearch_config',
  :description => 'Proximity URL for elasticsearch.yml file',
  :default => 'https://repository.walmart.com/content/repositories/pangaea_releases/com/walmart/strati/af/df/managed_es/configs/sample-es-6-6-0/es-cluster-conf/1.0.2/es-cluster-conf-1.0.2.jar',
  :format => {
      :help => 'Proximity URL for elasticsearch.yml file',
      :category => '1.Cluster',
      :important => true,
      :order => 3
  }

attribute 'master',
  :description => "Master",
  :default => 'true',
  :format => {
      :help => 'Set this to true if this is the elasticsearch-master platform',
      :category => '1.Cluster',
      :order => 4
  }

attribute 'data',
  :description => "Data",
  :default => 'true',
  :format => {
      :help => 'Set this to true if this is the elasticsearch-data platform',
      :category => '1.Cluster',
      :order => 5
  }

attribute 'memory',
  :description => "Allocated Memory(GB)",
  :default => '1g',
  :format => {
    :important => true,
    :help => 'Allocated Memory to elastic search. Ideally should be 24g for a full production system',
    :category => '2.Memory',
    :order => 1
  }

recipe "status", "Es Status"
recipe "stop", "Stop Es"
recipe "start", "Start Es"
recipe "restart", "Restart Es"