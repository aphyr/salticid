class Hydra::Task
  # A named block, runnable in some context
  attr_accessor :name, :block

  def initialize(name, opts = {})
    @name = name.to_s
  end

  def ==(other)
    self.name == other.name and
    self.block == other.block
  end

  def dup
    dup = Hydra::Task.new(@name)
    dup.block = @block 
    dup
  end

  def inspect
    "#<Task #{@name}>"
  end

  # Sets or gets the name of this task.
  def name(name = nil)
    if name
      @name = name.to_s
    else
      @name
    end
  end

  # Runs the task in a given context
  def run(context = nil, *args)
    if context
      begin
        context.instance_exec(*args, &@block)
      rescue Exception => err
        puts "[task: #{name}] #{err.message}"
        puts err.backtrace.grep(/deploy/).join("\n")
        raise err
      end
    else
      @block.call(*args)
    end
  end

  def to_s
    @name.to_s
  end

  def to_string
    "Task #{self}"
  end
end
