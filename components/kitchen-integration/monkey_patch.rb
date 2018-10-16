require 'fileutils'

=begin

Address hashie warning spam.

https://github.com/berkshelf/berkshelf/pull/1668

=end
require "hashie"
require "hashie/logger"
Hashie.logger = Logger.new(nil)

require "kitchen"
require "kitchen/version"

module Kitchen
  class Instance
    def converge_action
      if !verifier[:transport].eql?("local")
        banner "Converging #{to_str}..."

        elapsed = action(:converge) do |state|
          if legacy_ssh_base_driver?
            legacy_ssh_base_converge(state)
          else
            provisioner.call(state)
          end
        end
        info("Finished converging #{to_str} #{Util.duration(elapsed.real)}.")
      else
        banner "Skipping converging step"
      end
      self
    end 

    def legacy_ssh_base_setup(state)
      warn("Running legacy setup for '#{driver.name}' Driver")
      # TODO: Document upgrade path and provide link
      # warn("Driver authors: please read http://example.com for more details.")
      if !verifier[:transport].nil? && !verifier[:transport].eql?('local')
        driver.setup(state)
      else
        banner "Skipping #{driver.name} setup step"
      end
    end
  end
end 


module Kitchen
  module Driver
    class Proxy < Kitchen::Driver::SSHBase
      def reset_instance(state)
        if config[:transport] && config[:transport].eql?("local")
          info("Transport mode #{config[:transport]} so no-ops")
        else
          if cmd = config[:reset_command]
            info("Resetting instance state with command: #{cmd}")
            ssh(build_ssh_args(state), cmd)
          end
        end
      end
    end
  end
end

=begin
  
Monkey patch ridley/chef/cookbook/metadata to safeguard
in scenario where name is not lowercase in metadata. 

=end
require "ridley"

module Ridley::Chef
  class Cookbook
    class Metadata
      def name(arg = nil)
        arg = arg.nil? ? nil : arg.downcase
        set_or_return(
          :name,
          arg,
          :kind_of => [ String ]
        )
      end
    end
  end
end

require 'kitchen/verifier/serverspec'

# Monkey-patching kitchen-verifier-serverspec to use shellout instead of
# kernel.system, to correctly handle failures, i.e. re-translate exit code.
# This is fixed in the newer versions of the kitchen-verifier-serverspec gem,
# but we cannot use them due to different gem dependencies and a gem conflict:
# kitchen-verifier-serverspec (>0.4.0) depends on net-ssh ~> 3.0
# and at the same time chef-11.18.12 depends on net-ssh ~> 2.6
module Kitchen
  module Verifier
    # Serverspec verifier for Kitchen.
    class Serverspec < Kitchen::Verifier::Base
      def serverspec_commands
        if config[:remote_exec]
          if custom_serverspec_command
            <<-INSTALL
            #{custom_serverspec_command}
            INSTALL
          else
            <<-INSTALL
            #{config[:additional_serverspec_command]}
            mkdir -p #{config[:default_path]}
            cd #{config[:default_path]}
            RSPEC_CMD=#{rspec_bash_cmd}
            echo "---> RSPEC_CMD variable is: ${RSPEC_CMD}"
            #{rspec_commands}
            #{remove_default_path}
            INSTALL
          end
        elsif custom_serverspec_command
          shellout custom_serverspec_command
        else
          if config[:additional_serverspec_command]
            c = config[:additional_serverspec_command]
            shellout c
          end
          c = rspec_commands
          shellout c
        end
      end

      def merge_state_to_env(state)
        env_state = { :environment => {} }
        env_state[:environment]['KITCHEN_INSTANCE'] = instance.name
        env_state[:environment]['KITCHEN_PLATFORM'] = instance.platform.name
        env_state[:environment]['KITCHEN_SUITE'] = instance.suite.name
        state.each_pair do |key, value|
          env_state[:environment]['KITCHEN_' + key.to_s.upcase] = value.to_s
          ENV['KITCHEN_' + key.to_s.upcase] = value.to_s
          info("Environment variable #{'KITCHEN_' + key.to_s.upcase} value #{value}")
        end
        # if using a driver that uses transport expose those too
        %w[username password ssh_key port].each do |key|
          next if instance.transport[key.to_sym].nil?
          value = instance.transport[key.to_sym].to_s
          ENV['KITCHEN_' + key.to_s.upcase] = value
          info("Transport Environment variable #{'KITCHEN_' + key.to_s.upcase} value #{value}")
        end
        config[:shellout_opts].merge!(env_state)
      end

      def rspec_bash_cmd
        config[:rspec_path] ? "#{config[:rspec_path]}/rspec" : '$(which rspec)'
      end
    end
  end
end

require 'kitchen/transport/rsync'

module Kitchen
  module Transport
    class Rsync < Ssh

      def create_new_connection(options, &block)
        if @connection
          logger.debug("[SSH] shutting previous connection #{@connection}")
          @connection.close
        end

        @connection_options = options
        @connection = self.class::Connection.new(options, &block)
      end

      class Connection < Ssh::Connection
        def upload(locals, remote)
          remote = remote.sub(/^([A-z]):\//, '/cygdrive/\1/')
          Array(locals).each do |local|
            full_remote = File.join(remote, File.basename(local))
            recursive = File.directory?(local)
            execute("mkdir -p #{full_remote}") if recursive
            time = Benchmark.realtime do
              ssh_command = [login_command.command, login_command.arguments[0..-2]].flatten.join(' ')
              sync_command = "rsync -e '#{ssh_command}' -a#{@logger.debug? ? 'v' : ''}z #{local} #{@session.options[:user]}@#{@session.host}:#{remote}"
              @logger.debug("[RSYNC] Running rsync command: #{sync_command}")
              system(sync_command)
            end
            logger.debug("[RSYNC] Time taken to upload #{local} to #{self}:#{full_remote}: %.2f sec" % time)
          end
        end
      end

    end
  end
end
