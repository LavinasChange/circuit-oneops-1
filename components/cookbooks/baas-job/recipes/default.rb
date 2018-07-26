require 'rubygems'
require 'net/https'
require 'json'

cloud_name = node[:workorder][:cloud][:ciName]
Chef::Log::info("Cloud name is " + cloud_name)

appUser = "#{node['baas-job']['app-user']}"
baasContext = "#{node['baas-job']['baas-context']}"
processOwner = "#{node['baas-job']['process-owner']}"
baasDir = "/" + appUser + "/" + baasContext
jobsDir = baasDir + "/jobs"
jobTypesDir = baasDir + "/jobtypes"
driverDir =  baasDir + "/" + "#{node['baas-job']['baas-driver-dir']}"
logsDir = baasDir + "/logs"

repo_url = ""

cloud_name = node[:workorder][:cloud][:ciName]
Chef::Log::info("Got cloud name as #{cloud_name}")

if node[:workorder][:payLoad].has_key?(:OO_LOCAL_VARS)
    local_vars = node.workorder.payLoad.OO_LOCAL_VARS
    local_vars_index = local_vars.index { |resource| resource[:ciName] == 'driver_repo_url' }

    if !local_vars_index.nil?
      repo_url = local_vars[local_vars_index][:ciAttributes][:value]
      Chef::Log::info("Got repo URL via local variable #{repo_url}")
    end
  end
  
# Look in the defined service if not set by cloud variable
if repo_url == ""
  if (!node[:workorder][:services]["maven"].nil?)
    repo_url = node[:workorder][:services]['maven'][cloud_name][:ciAttributes][:url]
    Chef::Log::info("Got repo url from cloud service as #{repo_url}")
  end
end
Chef::Log::info("Final resolution for repo url as #{repo_url}")

if repo_url == ""
  puts "***FAULT:FATAL=The Repo URL has not been specified. It needs to be set either by defining 'driver_repo_url' local variable in your platform or by adding 'nexus' service to your cloud by OneOps admins."
  e = Exception.new("no backtrace")
  e.set_backtrace("")
  raise e
end

### Create baas driver directory ###
Chef::Log::info("Creating the driver jar directory #{driverDir} if not present...")
directory driverDir do
	owner processOwner
	group processOwner
	mode '0777'
	recursive true
	action :create
end

### Download driver jar file ###
Chef::Log::info("Downloading the baas driver jar...")
driverRepoUrl = "#{repo_url}content/repositories/pangaea_releases/com/walmart/platform/baas/baas-oneops"
driverVersion = "#{node['baas-job']['driver-version']}"
Chef::Log.info("User-provided driver-version value == #{driverVersion}")
if driverVersion.to_s.empty?
  driverVersion = "#{node['baas-job']['driver-version']}"
  Chef::Log.info("Setting driverVersion value to default value == #{driverVersion}")
end

driverJarNexusUrl = driverRepoUrl + "/" + driverVersion + "/baas-oneops-" + driverVersion + ".jar"
Chef::Log::info("BaaS driver remote url: #{driverJarNexusUrl}")

remote_file "#{driverDir}/baas-oneops-#{driverVersion}.jar" do
	source driverJarNexusUrl
	owner processOwner
	group processOwner
	mode '0755'
	action :create_if_missing
end

### create logmon logs directory ###
directory '/log/logmon' do
    owner processOwner
    group processOwner
    mode '0777'
    recursive true
    action :create
end

### Retrieve parameters ###
driverId="#{node['baas-job']['driver-id']}"
if driverId.to_s.empty?
  Chef::Log.error("No driver ID found which is a mandatory field.")
  exit 1
end

### Process all provided jobtype 1 related job ID and artifacts ###
jobMap1 = "#{node['baas-job']['job_map_1']}"
cfg = JSON.parse(jobMap1)
Chef::Log.info"##conf_directive_entries: #{cfg}"
cfg.each_key { |key|
	val = BaasJsonHelper.parse_json(cfg[key]).to_s
    Chef::Log.info "#vsrpKIV-#{key}=#{val}"
    jobArtifactDir = jobsDir + "/" + key + "/artifact"
    
    Chef::Log::info("Creating the job scripts directory #{jobArtifactDir} if not present...")
	directory jobArtifactDir do
        owner processOwner
        group processOwner
        mode '0777'
        recursive true
        action :create
	end
	
	### Resolve name for job script file ###
	artifactRemoteUrl = "#{val}"
	Chef::Log.info("artifactRemoteUrl is " + artifactRemoteUrl)
	jobArtifactName = File.basename(artifactRemoteUrl)
	
	### Download job script file from remote location ###
	finalArtifactPath = jobArtifactDir + "/" + jobArtifactName
	Chef::Log::info("Downloading the job script file #{jobArtifactName} from #{artifactRemoteUrl}")
	remote_file finalArtifactPath do
        source artifactRemoteUrl 
        owner processOwner
        group processOwner
        mode '0777'
        action :create_if_missing
	end
}

### Process all provided jobtype 2 related job ID and artifacts ###
jobMap2 = "#{node['baas-job']['job_map_2']}"
cfg = JSON.parse(jobMap2)
Chef::Log.info"##conf_directive_entries: #{cfg}"
cfg.each_key { |key|
	val = BaasJsonHelper.parse_json(cfg[key]).to_s
    Chef::Log.info "#vsrpKIV-#{key}=#{val}"
    jobArtifactDir = jobsDir + "/" + key + "/artifact"
    
    Chef::Log::info("Creating the job scripts directory #{jobArtifactDir} if not present...")
	directory jobArtifactDir do
        owner processOwner
        group processOwner
        mode '0777'
        recursive true
        action :create
	end
	
	### Resolve name for job script file ###
	artifactRemoteUrl = "#{val}"
	Chef::Log.info("artifactRemoteUrl is " + artifactRemoteUrl)
	jobArtifactName = File.basename(artifactRemoteUrl)
	
	### Download job script file from remote location ###
	finalArtifactPath = jobArtifactDir + "/" + jobArtifactName
	Chef::Log::info("Downloading the job script file #{jobArtifactName} from #{artifactRemoteUrl}")
	remote_file finalArtifactPath do
        source artifactRemoteUrl 
        owner processOwner
        group processOwner
        mode '0777'
        action :create_if_missing
	end
}     

if jobMap1.to_s.empty? 
  Chef::Log::warn("No entry found in job-map1")
  if jobMap2.to_s.empty?
    Chef::Log::error("No entry found in job-map2 as well, deployment cannot proceed")
    exit 1
  end
end

### Create job logs directory ###
Chef::Log::info("Creating the logs directory #{logsDir} if not present...")
directory logsDir do
        owner processOwner
        group processOwner
        mode '0777'
        recursive true
        action :create
end

### Extract artifacts from any tarballs ###
include_recipe "baas-job::extractfiles"

### Start BaaS driver application ###
include_recipe "baas-job::startdriver"

### Verify if the process started successfully ###
include_recipe "baas-job::status"

### END ###