
Chef::Log.info("activating windows")

if !node[:workorder][:services].has_key?('windows-domain')
  Chef::Log.error("windows-domain service is not configured in your cloud")
  exit 1
end

cloud_name = node[:workorder][:cloud][:ciName]
domain = node[:workorder][:services]['windows-domain'][cloud_name][:ciAttributes]
windows_domain = domain[:domain]

Chef::Log.info("Domain name: #{windows_domain}")

if windows_domain.nil? || windows_domain.empty? || windows_domain.split(".").length < 2
  Chef::Log.error("Unable to get domain, please check if windows-domain service is configured properly in the cloud")
  exit 1
end

kms_loopup_domain = windows_domain.split(".")[-2,2].join(".").downcase

slmgr = 'c:\windows\system32\slmgr.vbs'

powershell_script 'Activate-Windows' do
  code <<-EOH
  cscript #{slmgr} /ckms
  cscript #{slmgr} /skms-domain #{kms_loopup_domain}
  cscript #{slmgr} /ato
  EOH
  only_if <<-EOH
  	$sls = Get-WMIObject -query "select * from SoftwareLicensingService"
  	$kmsdomain = $sls.KeyManagementServiceLookupDomain
  	([string]::IsNullOrEmpty($kmsdomain)) -Or ($kmsdomain.ToLower() -ne #{kms_loopup_domain})
  EOH
end
