class Symbol
  # Helper method for File.join
  def /(*args)
    File.join(self.to_s, *args.map {|e| e.to_s})
  end
end
