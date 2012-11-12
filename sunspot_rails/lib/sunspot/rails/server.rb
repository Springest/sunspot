module Sunspot
  module Rails
    class Server < Sunspot::Solr::Server
      # ActiveSupport log levels are integers; this array maps them to the
      # appropriate java.util.logging.Level constant
      LOG_LEVELS = %w(FINE INFO WARNING SEVERE SEVERE INFO)

      #
      # Run the sunspot-solr server in the foreground. Boostrap
      # solr_home first, if neccessary.
      #
      # ==== Returns
      #
      # Boolean:: success
      #
      def run
        bootstrap

        command = ['java']
        command << "-Xms#{min_memory}" if min_memory
        command << "-Xmx#{max_memory}" if max_memory
        command << "-Djetty.port=#{port}" if port
        command << "-Djetty.host=#{bind_address}" if bind_address
        command << "-Dsolr.solr.home=#{solr_home}" if solr_home
        command << "-Dsolr.data.dir=#{solr_data_dir}" if solr_data_dir
        command << "-Dsolr.enable.replication=true" if ::Rails.env.production?
        command << "-Dsolr.enable.master=true" if ENV["SOLR_MASTER"]
        command << "-Dsolr.enable.slave=true" if !ENV["SOLR_MASTER"]
        command << "-Djava.util.logging.config.file=#{logging_config_path}" if logging_config_path
        command << '-jar' << File.basename(solr_jar)
        FileUtils.cd(File.dirname(solr_jar)) do
          exec(Shellwords.shelljoin(command))
        end
      end

      def stop
        if File.exist?(pid_path)
          pid = IO.read(pid_path).to_i
          begin
            Process.kill('TERM', pid)
          rescue Errno::ESRCH
            raise NotRunningError, "Process with PID #{pid} is no longer running"
          ensure
            FileUtils.rm(pid_path)
            remove_stale_processes(pid)
          end
        else
          remove_stale_processes
          raise NotRunningError, "No PID file at #{pid_path}"
        end
      end

      def bootstrap
        super unless ::Rails.env.production?
      end

      def kill_pid(pid)
        begin
          Process.kill('TERM', pid)
        rescue Errno::ESRCH
        end
      end

      def remove_stale_processes(except_pid=nil)
        puts "Looking for stale solr processes.."
        # Hack to kill all processes that failed to quit.
        ps = `ps -eo pid,ppid,comm,args | grep Dsolr`
        pids = ps.split("\n").select { |p|
            !p.match(/grep/) && !p.match(/Djetty.port=8981/)
          }.map { |p|
            p.chomp.split(" ").first.to_i
          }.select{ |p| p != except_pid }
        pids.each{|p| kill_pid p }
        puts "Killed #{pids.size} stale Solr processes."
      end

      #
      # Directory in which to store PID files
      #
      def pid_dir
        if ::Rails.env.production?
          "/data/springest/shared/solr/pids"
        else
          configuration.pid_dir || File.join(::Rails.root, 'tmp', 'pids')
        end
      end

      #
      # Name of the PID file
      #
      def pid_file
        "sunspot-solr-#{::Rails.env}.pid"
      end

      #
      # Directory to store lucene index data files
      #
      # ==== Returns
      #
      # String:: data_path
      #
      def solr_data_dir
        if ::Rails.env.production?
          "/data/springest/shared/solr/data/production"
        else
          configuration.data_path
        end
      end

      #
      # Directory to use for Solr home.
      #
      def solr_home
        File.join(configuration.solr_home)
      end

      #
      # Solr start jar
      #
      def solr_jar
        configuration.solr_jar || super
      end

      #
      # Address on which to run Solr
      #
      def bind_address
        configuration.bind_address
      end

      #
      # Port on which to run Solr
      #
      def port
        configuration.port
      end

      #
      # Severity level for logging. This is based on the severity level for the
      # Rails logger.
      #
      def log_level
        LOG_LEVELS[::Rails.logger.level]
      end

      #
      # Log file for Solr. File is in the rails log/ directory.
      #
      def log_file
        File.join(::Rails.root, 'log', "sunspot-solr-#{::Rails.env}.log")
      end

      #
      # Minimum Java heap size for Solr
      #
      def min_memory
        configuration.min_memory
      end

      #
      # Maximum Java heap size for Solr
      #
      def max_memory
        configuration.max_memory
      end

      private

      #
      # access to the Sunspot::Rails::Configuration, defined in
      # sunspot.yml. Use Sunspot::Rails.configuration if you want
      # to access the configuration directly.
      #
      # ==== returns
      #
      # Sunspot::Rails::Configuration:: configuration
      #
      def configuration
        Sunspot::Rails.configuration
      end
    end
  end
end
