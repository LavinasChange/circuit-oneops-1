module StorageComponent
  class Storage
    attr_reader :storage_service, :storage_account_name
    # Azure specific implementation for unmanaged storage
    # Gets the list of volumes with names matching component ciName+ciID
    # Which essentially is a list of all volumes already deployed
    # for the particular storage component
    # Returns an array of hashes
    def load_storage_devices
      storage_service

      blob_pattern = [@storage_account_name,@rfcCi['ciId'].to_s,'datadisk'].
        join('-') + '\S+\.vhd'
      volumes = @storage_service.list_blobs('vhds')[:blobs].select do |b|
        b.name =~ /#{blob_pattern}/
      end

      arr = volumes.map do |v|
        { 'id'      => v.name.sub('.vhd', '').split('-')[1..-1].join('-'),
          'size_gb' => (v.properties[:content_length].to_f/1024**3).to_i }
      end
      arr || []
    end

    #
    def storage_service
      @vm = vm
      @storage_account_name = @vm.storage_account_name

      creds = service_credentials
      
      base_storage_service = Fog::Storage::AzureRM.new(creds)
      access_keys = base_storage_service.get_storage_access_keys(@rg_name, @storage_account_name)[1].value

      creds[:azure_storage_access_key] = access_keys
      creds[:azure_storage_account_name] = @storage_account_name

      @storage_service = Fog::Storage::AzureRM.new(creds)
    end

    # Returns credentials from @service
    def service_credentials
      base_storage_service = @service.instance_variable_get('@storage_service')
      {
        'tenant_id' => base_storage_service.instance_variable_get('@tenant_id'),
        'client_id' => base_storage_service.instance_variable_get('@client_id'),
        'client_secret' => base_storage_service.instance_variable_get('@client_secret'),
        'subscription_id' => base_storage_service.instance_variable_get('@subscription_id')
      }
    end

    def get_azure_storage_service(creds, resource_group, storage_account_name)
      creds[:azure_storage_access_key] = Fog::Storage::AzureRM.new(creds).get_storage_access_keys(resource_group, storage_account_name)[1].value
      creds[:azure_storage_account_name] = storage_account_name
      return Fog::Storage::AzureRM.new(creds)
    end

    #Returns server object
    def vm
      compute_attr = @node[:workorder][:payLoad][:DependsOn].detect do |d|
        d[:ciClassName].split('.').last == 'Compute'
      end[:ciAttributes]

      @service.servers(:resource_group => @rg_name).
        get(@rg_name, compute_attr[:instance_name])
    end

    def parse_device_map(_volume_dev)
      arr = _volume_dev.split(':')
      if arr.size == 5
        master_rg, storage_account_name, ciID, slice_size, dev = arr
        vol = [storage_account_name,ciID,'datadisk',dev.split('/').last.to_s].join('-')
      else
        dev, vol = nil, nil
      end
      return vol, dev
    end

    def device_map
      ciAttr = @rfcCi[:ciAttributes]
      device_map_attr = [] 
      device_map_attr = ciAttr['device_map'].split(' ') if ciAttr.key?('device_map')
      device_map = []
      @storage_devices.each_with_index do |sd, i|
        _dev = device_map_attr.detect{ |dm| parse_device_map(dm) == sd['id'] }
        unless _dev
          _dev = [@rg_name,
                  @storage_account_name,
                  @rfcCi[:ciId].to_s,
                  sd['size_gb'].to_s,
                  planned_device_id(i+1)].join(':')
        end

        device_map.push(_dev)
      end
      device_map
    end
  end
end
