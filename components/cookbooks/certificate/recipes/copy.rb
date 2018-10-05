if node.workorder.payLoad.has_key?("ManagedVia") && (! node.has_key?("persist_cert") || node[:persist_cert] == true)
           cert_path = node[:certificate][:path]
           ci_name = node.workorder.rfcCi.ciName
           trim_ciname = "#{ci_name}".rpartition('-')[0].rpartition('-')[0]
           path = "#{cert_path}/#{trim_ciname}"
           cname = node.workorder.rfcCi.ciAttributes.common_name
           cer_cont = node[:cert_content]
           key_cont = node[:key_content]
           ca_cont = node[:ca_content]
           pfx_cont = node[:pfx_content]
           `mkdir -p #{path}`
           File.open("#{path}/#{cname}.pem", "w") {|line| line.puts "\r" + cer_cont.to_s }
           File.open("#{path}/#{cname}.key", "w") {|line| line.puts "\r" + key_cont.to_s }
           File.open("#{path}/ca_cert.crt", "w") {|line| line.puts "\r" + ca_cont.to_s }
           File.open("#{path}/#{cname}.pfx", "w") {|line| line.puts "\r" + pfx_cont.to_s }
end
