module StorageComponent
  class Storage
    attr_reader :rg_name

    def load_cloud_defaults
      puts 'Loading Azure defaults'
      utils = File.expand_path('../../../../azure_base/libraries/utils.rb',
        __FILE__)
      require utils
      rg_manager = AzureBase::ResourceGroupManager.new(@node)
      as_manager = AzureBase::AvailabilitySetManager.new(@node)
      @rg_name = rg_manager.rg_name
      av_set = @service.availability_sets.get(@rg_name, as_manager.as_name)
      if av_set.sku_name != 'Aligned'
        load File.expand_path('../azurerm_unmanaged.rb', __FILE__)
      end
      @storage_devices = load_storage_devices
    end

    # Azure specific implementation
    # Gets the list of volumes with names matching component ciName+ciID
    # Which essentially is a list of all volumes already deployed
    # for the particular storage component
    # Returns an array of hashes
    def load_storage_devices
      volumes = @service.list_managed_disks_by_rg(@rg_name).select do |v|
        v.name =~ /#{@name_pattern}/
      end
      arr = volumes.map{ |v| { 'id' => v.name, 'size_gb' => v.disk_size_gb } }
      arr || []
    end

    def planned_device_id(slice_num)
      device_letters = ('b'..'v').to_a
      "/dev/sd#{device_letters[slice_num]}"
    end
  end
end
