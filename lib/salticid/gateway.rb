class Salticid::Gateway < Salticid::Host
  def initialize(*args)
    @tunnel_lock = Mutex.new
    super *args
  end

  # Gateways don't need gateways.
  def gw
  end

  # Tunnel for connecting to other hosts.
  def gateway_tunnel
    # Multiple hosts will be asking for this tunnel at the same time.
    # We need to only create one.
    @tunnel_lock.synchronize do
      @gateway_tunnel ||= Net::SSH::Gateway.new(name, user)
    end
  end

  # We don't need tunnels either
  def tunnel
  end
end
