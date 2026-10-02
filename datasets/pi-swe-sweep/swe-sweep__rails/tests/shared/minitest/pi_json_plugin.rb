require 'json'
module Minitest
  class PIJSONReporter < AbstractReporter
    def record(result)
      status = result.skipped? ? 'skipped' : (result.passed? ? 'passed' : 'failed')
      File.open(ENV.fetch('PI_MINITEST_REPORT'), 'a') do |file|
        file.flock(File::LOCK_EX)
        file.puts(JSON.generate({'id' => "#{result.klass}##{result.name}", 'outcome' => status}))
      end
    end
  end
  def self.plugin_pi_json_init(options)
    self.reporter << PIJSONReporter.new
  end
end
