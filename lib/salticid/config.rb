module Salticid
  def self.config
    @config
  end

  def self.config=(config)
    @config = config
  end

  def self.load_config(file)
    @config = Construct.load(file)

    @config.define :hosts, :default => []

    @config
  end
end
