module AzureCompute
  class VirtualMachineManager
    require File.expand_path('../../../compute/libraries/compute_util', __FILE__)
    attr_accessor :compute_service,
                  :initial_user,
                  :private_ip,
                  :ip_type,
                  :fast_image_flag,
                  :compute_ci_id,
                  :resource_group_name,
                  :server_name,
                  :creds,
                  :compute_client,
                  :storage_profile,
                  :network_profile,
                  :virtual_machine_lib,
                  :availability_set_response,
                  :tags,
                  :availability_set_name

    def initialize(node)
      @cloud_name = node['workorder']['cloud']['ciName']
      @compute_service = node['workorder']['services']['compute'][@cloud_name]['ciAttributes']
      @keypair_service = node['workorder']['payLoad']['SecuredBy'].first
      @server_name = node['server_name']
      @resource_group_name = node['platform-resource-group']
      @availability_set_name = node['platform-availability-set']
      @location = @compute_service[:location]
      @initial_user = @compute_service[:initial_user]
      @express_route_enabled = @compute_service['express_route_enabled']
      @secgroup_id = get_security_group_id(node)
      @image_id = node['image_id'].split(':')
      @oosize_id = node[:oosize_id]
      @ip_type = node['ip_type']
      @platform = platform(node)

      @platform_ci_id = node['workorder']['box']['ciId']
      @compute_ci_id = node['workorder']['rfcCi']['ciId']
      @tags = {}
      @is_new_cloud = Utils.is_new_cloud(node)

      # Fast image vars
      @FAST_IMAGE   = false
      @TESTING_MODE = false
      @fast_image_flag = false
      @ostype = node[:ostype]
      if node[:workorder].has_key?('config') && node[:workorder][:config].has_key?('FAST_IMAGE')
        @FAST_IMAGE = node[:workorder][:config][:FAST_IMAGE].to_s.downcase
      end
      if node[:workorder].has_key?('config') && node[:workorder][:config].has_key?('TESTING_MODE')
        @TESTING_MODE = node[:workorder][:config][:TESTING_MODE].to_s.downcase
      end
      #----------------

      @creds = {
          tenant_id: @compute_service['tenant_id'],
          client_secret: @compute_service['client_secret'],
          client_id: @compute_service['client_id'],
          subscription_id: @compute_service['subscription']
      }

      @compute_client = Fog::Compute::AzureRM.new(@creds)
      @network_client = Fog::Network::AzureRM.new(@creds)
      @virtual_machine_lib = AzureCompute::VirtualMachine.new(@creds)
      @storage_profile = AzureCompute::StorageProfile.new(@creds)
      @network_profile = AzureNetwork::NetworkInterfaceCard.new(@creds)
      @availability_set_response = @compute_client.availability_sets.get(@resource_group_name, @availability_set_name)

      @size_id = get_vm_size_id(node)

      @accelerated_networking = if (defined?(node[:workorder][:rfcCi][:ciAttributes][:accelerated_flag]))
        node[:workorder][:rfcCi][:ciAttributes][:accelerated_flag]
      else
        false
      end

      if @platform == 'windows'
        mirror_svc = node[:workorder][:services][:mirror]
        if !mirror_svc.nil?
          cloud = node.workorder.cloud.ciName
          mirror = JSON.parse(mirror_svc[cloud][:ciAttributes][:mirrors])
          cygwin_url = mirror['cygwin_url']
          cygwin_packages_url = mirror['cygwin_packages_url']
        end

        @cygwin_url = (cygwin_url.nil? || cygwin_url.empty?) ? "https://cygwin.com/setup-x86_64.exe" : cygwin_url
        @cygwin_packages_url = (cygwin_packages_url.nil? || cygwin_packages_url.empty?) ? "http://cygwin.mirror.constant.com/" : cygwin_packages_url

      end

      if @accelerated_networking.eql? 'true' && !@ostype.nil?
        OOLog.fatal "Accelerated Network is only available for CentOS 7.4" unless @ostype.eql? 'centos-7.4'
      end
    end

    def create_or_update_vm
      OOLog.info('Resource group name: ' + @resource_group_name)

      @ip_type = 'public'
      @ip_type = 'private' if @express_route_enabled == 'true'
      OOLog.info('ip_type: ' + @ip_type)

      @storage_profile.resource_group_name = @resource_group_name
      @storage_profile.location = @location
      @storage_profile.size_id = @size_id
      @storage_profile.ci_id = @platform_ci_id
      @storage_profile.server_name = @server_name

      if (defined?(node[:workorder][:rfcCi][:ciAttributes][:private_ip]) && node[:workorder][:rfcCi][:rfcAction] == 'update')
        @network_profile.flag = true
        @network_profile.private_ip = node[:workorder][:rfcCi][:ciAttributes][:private_ip]
      else
        @network_profile.flag = false
      end
      @network_profile.location = @location
      @network_profile.rg_name = @resource_group_name
      @network_profile.ci_id = @compute_ci_id
      @network_profile.platform_ci_id = @platform_ci_id if @is_new_cloud
      @network_profile.tags = @tags
      # build hash containing vm info
      # used in Fog::Compute::AzureRM::create_virtual_machine()
      vm_hash = {}

      # common values
      vm_hash[:tags] = @tags
      vm_hash[:name] = @server_name
      vm_hash[:resource_group] = @resource_group_name

      vm_hash[:availability_set_id] = @availability_set_response.id
      vm_hash[:location] = @compute_service[:location]

      # hardware profile values
      vm_hash[:vm_size] = @size_id if @availability_set_response.sku_name.eql? 'Aligned'
      vm_hash[:vm_size] = @storage_profile.get_old_azure_mapping(@oosize_id) if @availability_set_response.sku_name.eql? 'Classic'


      # storage profile values

      vm_hash[:storage_account_name] = @storage_profile.get_managed_osdisk_name if @availability_set_response.sku_name.eql? 'Aligned'
      vm_hash[:storage_account_name] = @storage_profile.get_storage_account_name if @availability_set_response.sku_name.eql? 'Classic'

      customimage_resource_group = @compute_service['resource_group'].sub("mrg","img")

      # Fast image logic
      OOLog.info("FAST_IMAGE_Flag: #{@FAST_IMAGE}, TESTING_MODE_FLAG: #{@TESTING_MODE}")
      if @FAST_IMAGE =~ /true/i
        begin

          # connection
          azure_client = get_azure_connection(@creds)
          # get image list
          images = azure_client.resource_groups.list_resources(customimage_resource_group)

          # find fast image

          # get_image(
          # image list,               # array of objects: List of images. must have name for each. example: images[i].name
          # flavor,                   # object, nil: Flavor object can be nil
          # fast image cms switch,    # bool, string, nil: cms flag
          # testing mode cms switch,  # bool, string, nil: cms flag
          # default image,            # object, nil: default image option for openstack
          # custom id?,               # bool: custom id option for openstack
          # ostype                    # must be in format of "type-major.minor"
          # )
          fast_image = get_image(images, nil, @FAST_IMAGE, @TESTING_MODE, nil, false, @ostype)

        rescue MsRestAzure::AzureOperationError => e
          OOLog.debug("Error Body: #{e.body}")
          OOLog.fatal('Error getting list of images')
        end
      end



      # if not fast do old way
      if !fast_image.nil?
        image_ref           = "/subscriptions/#{@compute_service['subscription']}/resourceGroups/#{customimage_resource_group}/providers/Microsoft.Compute/images/#{fast_image.name}"
        vm_hash[:image_ref] = image_ref
        @fast_image_flag    = true

        OOLog.info('image ref: ' + image_ref )
      elsif @image_id[0].eql? 'Custom'
        azure_client = get_azure_connection(@creds)

        images = azure_client.resource_groups.list_resources(customimage_resource_group)
        custom_image = get_custom_image(images, @ostype, @image_id)

        exit_with_error "Custom Image for OS Type #{@ostype} is Not Available!" if custom_image.nil?

        image_ref           = "/subscriptions/#{@compute_service['subscription']}/resourceGroups/#{customimage_resource_group}/providers/Microsoft.Compute/images/#{custom_image.name}"
        vm_hash[:image_ref] = image_ref
        pattern             = /[a-zA-Z]{1,20}-#{@ostype.gsub(/\./, "")}-\d{4}-v\d{8}-\d{4}/i
        @fast_image_flag    = false
        OOLog.info('image ref: ' + image_ref )
      else
        vm_hash[:publisher] = @image_id[0]
        vm_hash[:offer]     = @image_id[1]
        vm_hash[:sku]       = @image_id[2]
        vm_hash[:version]   = @image_id[3]
        @fast_image_flag    = false
      end
      # -------------

      vm_hash[:platform] = @platform

      vm_hash[:managed_disk_storage_type] = @storage_profile.get_managed_osdisk_type if @availability_set_response.sku_name.eql? 'Aligned'

      # os profile values
      vm_hash[:username] = @initial_user

      if @platform == 'windows'
        vm_hash[:password] = @virtual_machine_lib.get_random_password
      else
        vm_hash[:disable_password_authentication] = true
      end

      vm_hash[:ssh_key_data] = @keypair_service[:ciAttributes][:public]
      # network profile values
      nic_id = @network_profile.build_network_profile(@compute_service[:express_route_enabled],
                                                      @compute_service[:resource_group],
                                                      @compute_service[:network],
                                                      @compute_service[:network_address].strip,
                                                      (@compute_service[:subnet_address]).split(','),
                                                      (@compute_service[:dns_ip]).split(','),
                                                      @ip_type,
                                                      @secgroup_id,
                                                      @accelerated_networking)

      vm_hash[:network_interface_card_ids] = [nic_id]

      @private_ip = @network_profile.private_ip
      # create the virtual machine
      begin
        virtual_machine = @virtual_machine_lib.create_update(vm_hash)
        if @platform == 'windows'
          vm_hash[:cygwin_url] = @cygwin_url
          vm_hash[:cygwin_packages_url] = @cygwin_packages_url
          @virtual_machine_lib.create_virtual_machine_extension(vm_hash)
        end
        virtual_machine

      rescue MsRestAzure::AzureOperationError => e
        OOLog.debug("Error Body: #{e.body}")
        OOLog.fatal('Error creating/updating VM')
      end
    end

    def delete_vm
      OOLog.info('cloud_name is: ' + @cloud_name)
      OOLog.info('Subscription id is: ' + @compute_service[:subscription])
      start_time = Time.now.to_i
      @ip_type = 'public'
      @ip_type = 'private' if @express_route_enabled == 'true'
      OOLog.info('ip_type: ' + @ip_type)
      begin
        vm_exists = @virtual_machine_lib.check_vm_exists?(@resource_group_name, @server_name)
        vm = nil
        vm = @virtual_machine_lib.get(@resource_group_name, @server_name) if vm_exists
        if vm.nil?
          OOLog.info("VM '#{@server_name}' was not found. Nothing to delete. ")
          os_disk_name = "#{@server_name.to_s}_os_disk"
          return os_disk_name, nil
        else

          os_disk = vm.os_disk_name

          datadisk_uri = nil
          datadisk_uri = vm.data_disks[0].vhd_uri if vm.data_disks.count > 0
          OOLog.info("Deleting Azure VM: '#{@server_name}'")
          # delete the VM from the platform resource group

          OOLog.info('VM is deleted') if @virtual_machine_lib.delete(@resource_group_name, @server_name)
        end
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Error deleting VM, resource group: #{@resource_group_name}, VM name: #{@server_name}. Exception is=#{e.body}")
      rescue => ex
        OOLog.fatal("Error deleting VM, resource group: #{@resource_group_name}, VM name: #{@server_name}. Exception is=#{ex.message}")
      ensure
        end_time = Time.now.to_i
        duration = end_time - start_time
        OOLog.info("Deleting VM took #{duration} seconds")
      end

      return os_disk, datadisk_uri

    end

    def delete_unmanaged_vm
      OOLog.info('cloud_name is: ' + @cloud_name)
      OOLog.info('Subscription id is: ' + @compute_service[:subscription])
      start_time = Time.now.to_i
      @ip_type = 'public'
      @ip_type = 'private' if @express_route_enabled == 'true'
      OOLog.info('ip_type: ' + @ip_type)
      begin
        vm_exists = @virtual_machine_lib.check_vm_exists?(@resource_group_name, @server_name)
        vm = nil
        vm = @virtual_machine_lib.get(@resource_group_name, @server_name) if vm_exists
        if vm.nil?
          OOLog.info("VM '#{@server_name}' was not found. Nothing to delete. ")
          return nil, nil, nil
        else
          # retrive the vhd name from the VM properties and use it to delete the associated VHD in the later step.
          vhd_uri = vm.os_disk_vhd_uri
          storage_account = vm.storage_account_name
          datadisk_uri = nil
          datadisk_uri = vm.data_disks[0].vhd_uri if vm.data_disks.count > 0
          OOLog.info("Deleting Azure VM: '#{@server_name}'")
          # delete the VM from the platform resource group

          OOLog.info('VM is deleted') if @virtual_machine_lib.delete(@resource_group_name, @server_name)
        end
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Error deleting VM, resource group: #{@resource_group_name}, VM name: #{@server_name}. Exception is=#{e.body}")
      rescue => ex
        OOLog.fatal("Error deleting VM, resource group: #{@resource_group_name}, VM name: #{@server_name}. Exception is=#{ex.message}")
      ensure
        end_time = Time.now.to_i
        duration = end_time - start_time
        OOLog.info("Deleting VM took #{duration} seconds")
      end
      return storage_account, vhd_uri, datadisk_uri
    end

    def get_security_group_id(node)
      secgroup = node['workorder']['payLoad']['DependsOn'].detect {|d| d['ciClassName'] =~ /Secgroup/}
      if secgroup.nil?
        OOLog.fatal("No Secgroup found in workorder. This is required for VM creation.")
      else
        secgroup['ciAttributes']['net_sec_group_id']
      end
    end

    def get_vm_size_id(node)
      rfcCi = node['workorder']['rfcCi']
      return nil if rfcCi['rfcAction'] == 'delete'

      sizemap = JSON.parse(@compute_service['sizemap'])
      size = rfcCi['ciAttributes']['size']
      size_id = sizemap[size]
      if size_id.nil?
        OOLog.info("Size #{size} not found in cloud config, using direct size.")

        mgmt = @compute_client.instance_variable_get('@compute_mgmt_client')
        sizes = mgmt.instance_variable_get('@virtual_machine_sizes').list(@location).value
        if sizes.detect{ |s| s.name == size}
          return size
        else
          OOLog.fatal("The selected size #{size} is invalid")
        end
      end

      return size_id unless Utils.valid_json?(size_id)

      node['workorder']['payLoad']['RequiresComputes'].each do |compute|
        if compute['ciBaseAttributes'].key?(:size)
          old_size = compute['ciBaseAttributes']['size']
          new_size = compute['ciAttributes']['size']

          OOLog.info("Change in VM Size Detected. Old Size: #{old_size}. New Size: #{new_size}. Getting the latest flavor for new size")

          return pick_latest_vm_size(size_id) if new_size != old_size
        elsif compute['ciAttributes'].key?(:vm_size)
          OOLog.info('Getting the VM size flavor from the node')
          return compute['ciAttributes']['vm_size']
        end
      end

      vm_list = @virtual_machine_lib.get_resource_group_vms(@resource_group_name)

      vm_list = Utils.get_vms_per_pack(vm_list, node['workorder']['box']['ciName']) if @is_new_cloud

      if vm_list.count.eql? 0
        OOLog.info("No VM for size #{@oosize_id} is available. Fetching the latest flavor for size #{@oosize_id}")
        pick_latest_vm_size(size_id)
      else
        OOLog.info('Getting VM size from VMs found on the portal')
        vm = vm_list.first
        vm.vm_size
      end
    end

    def pick_latest_vm_size(vm_sizes)
      sizes_arr = JSON.parse(vm_sizes)
      sizes_arr.last
    end

    def platform(node)
      if node.key?('ostype')
        node['ostype'].downcase.include?('windows') ? 'windows' : 'linux'
      else
        @compute_service['ostype'].include?('windows') ? 'windows' : 'linux'
      end
    end

    private :get_security_group_id, :get_vm_size_id, :pick_latest_vm_size, :platform
  end
end
