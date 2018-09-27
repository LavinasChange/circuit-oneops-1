name             'Azureobjectstore'
maintainer       '@WalmartLabs'
maintainer_email 'umullangi@walmartlabs.com'
license          'All rights reserved'
description      'Installs/Configures azure objectstore service'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.0'
grouping 'default',
         :access => 'global',
         :packages => %w[base service.filestore mgmt.cloud.service cloud.service cloud.zone.service],
         :namespace => true
