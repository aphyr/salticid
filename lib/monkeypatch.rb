module Net
  module SSH
    class Shell
      # Like execute! but returns an array: the status and the output.
      def exec!(command, klass=Net::SSH::Shell::Process, &callback)
        result = ''

        process = klass.new(self, command, callback)
        process.on_output do |p, output|
          result << output
        end
        
        process.run if processes.empty?
        processes << process
        wait!
        
        [process.exit_status, result]
      end
    end
  end
end
