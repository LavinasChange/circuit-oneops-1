results = "/opt/cassandra/nodetool.out"
execute "date > #{results}"

args = ::JSON.parse(node.workorder.arglist)
v_custom_args = args["CustomNodetoolArg"]
v_custom_args = v_custom_args.to_s

## REMOVE LEADING SPACES
v_custom_args = v_custom_args.gsub(/^\s/,'')
## CHECK FOR EMPTY or INVALID ARGS
if v_custom_args !~ /\w/
    Chef::Log.error("NO ARGS FOUND>>>>>> " + v_custom_args)
    v_custom_args = "info"
end
if v_custom_args.eql? ''
    Chef::Log.error("INVALID ARG>>>>> " + v_custom_args)
    v_custom_args = "info"
end

Chef::Log.info("CHECKING FOR HOST Option Usage")
### FAIL IMMEDIATELY ON HOST OPTION ####
if v_custom_args =~ /^\-h\s*/i
    Chef::Log.error("HOST OPTION NOT SUPPORTED " + v_custom_args)
    exit 1
elsif v_custom_args =~ /^\-host\s*/i
    Chef::Log.error("HOST OPTION NOT SUPPORTED " + v_custom_args)
    exit 1
end

Chef::Log.info("USER IS ALLOWED FOR LEVEL 2")
Chef::Log.info("EXECUTE NODETOOL COMMAND")
Chef::Log.info("NODETOOL ARGUMENT----> " + v_custom_args)
execute "/opt/cassandra/bin/nodetool #{v_custom_args} &> /opt/cassandra/nodetool.out"


ruby_block "=======NODETOOL OUTPUT========" do
    only_if { ::File.exists?(results) }
    block do
        print "\n"
        File.open(results).each do |line|
            print line
        end
    end
end