require 'logger'

module RedLogger
  def self.logfile
    @logfile ||= File.open("./red.log", "w").tap do |f|
      f.sync = true
    end
  end

  def self.logger
    @logger ||= Logger.new(logfile)
  end
end

RedLogger.logger.level = Logger::WARN
