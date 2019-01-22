#
# Cookbook Name :: solrcloud
# Recipe :: delete_write_permissions_for_ro_user.rb
#
# The recipe will remove write permissions for the read only user (app-ro)
#
#


# Giving appropriate permissions for `other` users (read-only-user) for the directories like /app, /blockstorage, /app/solrdata*. /app/solrdata*/data, /app/solrdata*/logs
# Here `o-w` used in chmod, specifies that we are giving non-write permissions to other users (but read and execute are permitted)
bash "delete write permissions for ro user" do
  code <<-EOH
        declare -a arr=("/app" "/app/solrdata*" "/app/solrdata*/logs" "/blockstorage" "/app/solr_backup" "/opt" "/app/solr*")
        for i in "${arr[@]}"
        do
           echo "$i"
           if [ -d "$i" ]; then
              sudo chmod -R o-w $i
              sudo chmod -R o+r $i
              sudo chmod -R o+x $i
           fi
        done
  EOH
end