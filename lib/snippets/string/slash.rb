class String
  # Helper method for File.join
  def /(*args)
    File.join(self, *args.map {|e| e.to_s})
  end
end
