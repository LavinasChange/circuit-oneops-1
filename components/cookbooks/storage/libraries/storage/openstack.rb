module StorageComponent
  class Storage
    def load_cloud_defaults
      puts 'Loading Cinder defaults'
      @storage_devices = load_storage_devices
    end

    # Cinder specific implementation
    # Gets the list of volumes with names matching component ciName
    # Which essentially is a list of all volumes already deployed
    # for the particular storage component
    # Returns an array of hashes
    def load_storage_devices
      volumes = @service.volumes.all.select{ |v| v.name =~ /#{@name_pattern}/ }
      arr = volumes.map{ |v| { 'id' => v.id, 'size_gb' => v.size } }
      arr || []
    end

    def planned_device_id(slice_num)
      device_letters = ('b'..'v').to_a
      "/dev/vd#{device_letters[slice_num]}"
    end
  end
end
