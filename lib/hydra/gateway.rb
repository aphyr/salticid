class Hydra::Gateway < Hydra::Host
  # Gateways don't need gateways.
  def gw
  end

  # Tunnel for connecting to other hosts.
  def gateway_tunnel
    @gateway_tunnel ||= Net::SSH::Gateway.new(name, user)
  end

  # We don't need tunnels either
  def tunnel
  end
end
