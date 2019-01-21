module StorageComponent
  class Storage
    attr_reader :total_size_gb
    attr_accessor :storage_devices

    def initialize(node)
      # Overwrite cloud-specific methods and load cloud defaults
      libdir = File.join(File.dirname(__FILE__), 'storage')

      @service = node['storage_provider']
      @rfcCi = node['workorder']['rfcCi']
      @name_pattern = @rfcCi[:ciName] + '-' + @rfcCi[:ciId].to_s
      @node = node
      provider = @service.class.to_s[/Fog::(Compute|Volume)::([^:]*)/,2]
      @storage_devices = []
      if provider
        load File.join(libdir, "#{provider.downcase}.rb")
      else
        exit_with_error('Cannot determine Storage Provider')
      end
      load_cloud_defaults
      @total_size_gb = total_size_gb
    end

    def total_size_gb
      @storage_devices.map{ |sd| sd['size_gb'] }.inject(0, :+)
    end

    # Reconciles the array of storage devices from provider with the device_map
    # bom attribute from previous deployments
    # Returns an array of device_map values, which is a combination of storage
    # id and planned device id, and later is saved as a bom attribute
    def device_map
      ciAttr = @rfcCi[:ciAttributes]
      device_map_attr = [] 
      device_map_attr = ciAttr['device_map'].split(' ') if ciAttr.key?('device_map')
      device_map = []
      @storage_devices.each_with_index do |sd, i|
        _dev = device_map_attr.detect{ |dm| parse_device_map(dm) == sd['id'] }
        _dev = sd['id'] + ':' + planned_device_id(i+1) unless _dev
        device_map.push(_dev)
      end
      device_map
    end

    def parse_device_map(_volume_dev)
      vol, dev = _volume_dev.split(':')
      return vol, dev
    end
  end
end