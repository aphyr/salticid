class Message
  attr_reader :severity, :text, :time
  def initialize(*args)
    @text = args.pop
    @severity = args.first
    @time = Time.now
  end
end
