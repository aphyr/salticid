module Salticid::Host::IP
  # Host methods for IP addresses
  
  # Get all active IP addresses.
  def ips
    `ifconfig -a`.split("\n\n").map { |stanza|
      stanza.split("\n").find { |line|
        line =~ /inet addr:\s*([\d\.]{7..15})/
        $1
      }
    }.compact
  end

  def private_ips
  end

  def public_ips
  end
end
