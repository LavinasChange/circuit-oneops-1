module AzureCompute
  class VirtualMachine

    attr_reader :compute_service

    def initialize(credentials)
      @compute_service = Fog::Compute::AzureRM.new(credentials)
    end

    def get_resource_group_vms(resource_group_name)
      begin
        OOLog.info("Fetcing virtual machines in '#{resource_group_name}'")
        start_time = Time.now.to_i
        virtual_machines = @compute_service.servers(resource_group: resource_group_name)
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to get virtual machines #{vm_name} from resource group: #{resource_group_name}\n\r Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error getting VMs in resource group: #{resource_group_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_get_vms_in_rg=#{duration}" if ENV['KITCHEN_YAML'].nil?
      virtual_machines
    end

    def get(resource_group_name, vm_name)
      begin
        OOLog.info("Fetching VM '#{vm_name}' in '#{resource_group_name}' ")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.get(resource_group_name, vm_name)
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to get virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error fetching VM: #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_get_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      virtual_machine
    end

    def check_vm_exists?(resource_group_name, vm_name)
      begin
        start_time = Time.now.to_i
        exists = @compute_service.servers.check_vm_exists(resource_group_name, vm_name)
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to check VM: #{vm_params[:name]} existence. Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error checking VM: #{vm_params[:name]} existence. Error Message: #{e.message}")
      end
      OOLog.debug("VM Exists?: #{exists}")
      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_check_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      exists
    end

    def create_update(vm_params)
      begin
        OOLog.info("Creating/updating VM '#{vm_params[:name]}' in '#{vm_params[:resource_group]}' ")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.create(vm_params)
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to create/update virtual machine #{vm_params[:name]} from resource group: #{vm_params[:resource_group]}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error creating/updating VM: #{vm_params[:name]}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_create_update_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      virtual_machine
    end


    def create_virtual_machine_extension(vm_params)
      OOLog.info("Creating virtual machine extension '#{vm_params[:name]}' in '#{vm_params[:resource_group]}' ")
      ssh_keys = vm_params[:ssh_key_data]
      extension_name = 'mse'
      resource_group_name = vm_params[:resource_group]
      OOLog.info("Cygwin details: cygwin_url #{vm_params[:cygwin_url]} : cygwin_packages_url #{vm_params[:cygwin_packages_url]} ")

      extension_exists = @compute_service.virtual_machine_extensions.check_vm_extension_exists(resource_group_name, vm_params[:name], extension_name)
      if !extension_exists
        encoded_cmd = encoded_script(ssh_keys, vm_params[:cygwin_url], vm_params[:cygwin_packages_url])
        start_time = Time.now.to_i
        begin
        @compute_service.virtual_machine_extensions.create(
                name: extension_name,
                resource_group: resource_group_name,
                location: vm_params[:location],
                vm_name: vm_params[:name],            # Extension will be installed on this VM
                publisher: 'Microsoft.Compute',
                type: 'CustomScriptExtension',
                type_handler_version: '1.9',
                settings: {
                    "commandToExecute" => "powershell.exe -ExecutionPolicy Unrestricted -encodedCommand #{encoded_cmd}"
                }
        )
        rescue MsRestAzure::AzureOperationError => e
          cloud_error_data = e.body.inspect if e.body.is_a?(MsRestAzure::CloudErrorData)
          OOLog.fatal("Exception while creating VM extension #{extension_name} for #{vm_params[:name]} in resource group: #{vm_params[:resource_group]} exception: #{e.body} #{cloud_error_data}" )
        rescue => e
          OOLog.fatal("Error while creating VM extension: #{vm_params[:name]}. VM extension Error Message: #{e.message}")
        end
        end_time = Time.now.to_i
        duration = end_time - start_time
        OOLog.info("Operation: virtual machine extension creation took #{duration} seconds ")
        puts "***TAG:az_create_vm_extension=#{duration}" if ENV['KITCHEN_YAML'].nil?
      end
    end

    def delete(resource_group_name, vm_name)
      begin
        OOLog.info("Deleting VM '#{vm_name}' in '#{resource_group_name}' ")
        start_time = Time.now.to_i
        virtual_machine_exists = @compute_service.servers.check_vm_exists(resource_group_name, vm_name)
        if !virtual_machine_exists
          OOLog.info("Virtual Machine '#{vm_name}' was not found in '#{resource_group_name}', skipping deletion..")
        else
          virtual_machine = get(resource_group_name, vm_name).destroy
        end
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to delete virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error deleting VM: #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_delete_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      true
    end

    def start(resource_group_name, vm_name)
      begin
        OOLog.info("Starting VM: #{vm_name} in resource group: #{resource_group_name}")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.get(resource_group_name, vm_name)
        response = virtual_machine.start
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to start virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error starting VM. #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("VM started in #{duration} seconds")
      puts "***TAG:az_start_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      response
    end

    def restart(resource_group_name, vm_name)
      begin
        OOLog.info("Restarting VM: #{vm_name} in resource group: #{resource_group_name}")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.get(resource_group_name, vm_name)
        response = virtual_machine.restart
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to restart virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error restarting VM. #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_restart_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      response
    end

    def power_off(resource_group_name, vm_name)
      begin
        OOLog.info("Power off VM: #{vm_name} in resource group: #{resource_group_name}")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.get(resource_group_name, vm_name)
        response = virtual_machine.power_off
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to Power Off virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error powering off VM. #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_poweroff_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      response
    end

    def redeploy(resource_group_name, vm_name)
      begin
        OOLog.info("Redeploying VM: #{vm_name} in resource group: #{resource_group_name}")
        start_time = Time.now.to_i
        virtual_machine = @compute_service.servers.get(resource_group_name, vm_name)
        response = virtual_machine.redeploy
        end_time = Time.now.to_i
        duration = end_time - start_time
      rescue MsRestAzure::AzureOperationError => e
        OOLog.fatal("Azure::Virtual Machine - Exception trying to redeploy virtual machine #{vm_name} from resource group: #{resource_group_name}\n\rAzure::Virtual Machine - Exception is: #{e.body}")
      rescue => e
        OOLog.fatal("Error redeploying VM. #{vm_name}. Error Message: #{e.message}")
      end

      OOLog.info("operation took #{duration} seconds")
      puts "***TAG:az_redeploy_vm=#{duration}" if ENV['KITCHEN_YAML'].nil?
      response
    end

    def encoded_script(ssh_keys, cygwin_url, cygwin_packages_url)
      require 'base64'
      script = <<EOH
      $username = "oneops"
      $packages = "openssh,rsync,procps,cygrunsrv,lynx,wget,curl,bzip,tar,make,gcc-c,gcc-g++,libxml2"
      $path = 'C:\\Windows\\Temp'
      $arg_list = "-q -n -R C:\\cygwin64 -P $packages -s #{cygwin_packages_url}"
      try {
      if (!(Test-Path "C:\\cygwin64\\bin\\bash.exe")) {
        try {
          Invoke-WebRequest -Uri #{cygwin_url} -OutFile "$path\\CygwinSetup-x86_64.exe"
          Start-Process -PassThru -Wait -FilePath "$path\\CygwinSetup-x86_64.exe" -ArgumentList $arg_list
        }
        catch { exit 1 }
      }
      if (!(Get-Service sshd -ErrorAction Ignore)) {
        Invoke-Command -ScriptBlock {C:\\cygwin64\\bin\\bash.exe --login -i ssh-host-config -y -c "tty ntsec" -N "sshd" -u "cyg_server" -w "#{get_random_password}"}
        Invoke-Command -ScriptBlock {netsh advfirewall firewall add rule name="SSH-Inbound" dir=in action=allow enable=yes localport=22 protocol=tcp}
      }
      if ((Get-Service sshd).Status -ne "Running") {Start-Service sshd}
      }
      catch { exit 1 }
      Invoke-Command -ScriptBlock {net user $username "#{get_random_password}"  /add}
      Invoke-Command -ScriptBlock {net localgroup Administrators $username /add}
      $config_file = "C:/cygwin64/home/$($username)/.ssh/authorized_keys"
      if(!(Test-Path -Path $config_file)) { New-Item $config_file -type file -force }
      Add-Content $config_file -Value "#{ssh_keys}"
      Invoke-Command -ScriptBlock {icacls "C:/cygwin64/home/$($username)" /setowner $username /T /C /q}
      Invoke-Command -ScriptBlock {net user azure /logonpasswordchg:yes}
EOH
      encoded_cmd = Base64.strict_encode64(script.encode('utf-16le'))
      OOLog.info("encoded_cmd: #{encoded_cmd}")
      encoded_cmd
    end

    def get_random_password
      require 'securerandom'
      password = SecureRandom.base64(15)
      password = password[0..13] if password.size > 14
      password
    end


  end
end
