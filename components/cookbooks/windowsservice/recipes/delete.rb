windows_service = node['windowsservice']

windowsservice windows_service.service_name do
  action :stop
end

service_name = "\"Name='#{windows_service.service_name}'\""

powershell_script "delete windows service #{windows_service.service_name}" do
  code "Get-CimInstance -ClassName Win32_Service -Filter #{service_name} | Remove-CimInstance"
  only_if "Get-Service '#{windows_service.service_name}' -ErrorAction SilentlyContinue"
end
