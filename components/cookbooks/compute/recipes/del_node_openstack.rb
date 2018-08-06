def destroy(compute)
  begin
    compute.destroy     
  rescue Exception => e
    Chef::Log.error("delete failed: #{e.message}")
  end
end

conn = node['iaas_provider']
servers = conn.servers.all.select{ |s| s.name == node[:server_name] }

servers.each do |vm|
  id = vm.id
  Chef::Log.info("destroying server: #{vm.name}, id: #{id}")
  destroy(vm)

  # retry for 2min for server to be deleted
  ok=false
  attempt=0
  max_attempts=6
  while !ok && attempt < max_attempts
    server = conn.servers.get(id)
    if (server.nil? || server.os_ext_sts_task_state == 'deleting')
      ok = true
    else
      Chef::Log.info("Attempt: #{attempt}, state: #{server.state}. Retrying...")
      attempt += 1
      destroy(server)
      sleep 20
    end 
  end

  unless ok
    exit_with_error("Server still not removed after 7 attempts over 2min."\
      "Current state: #{conn.servers.get(id).state}")
  end
end
