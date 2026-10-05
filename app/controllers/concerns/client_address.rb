# The address a request came from, for rate limits.
#
# Rails' request.remote_ip believes any X-Forwarded-For entry outside its
# trusted proxies, and those include every private range (10/8, 172.16/12,
# 192.168/16), so a phone or laptop on the household Wi-Fi could name a new
# address on every request and start a fresh rate-limit count each time. Here
# only a proxy on this machine (Thruster in the Docker image) is believed,
# and only for the entry it appended last; any other peer is its own
# connection address.
module ClientAddress
  extend ActiveSupport::Concern

  private

  def client_ip
    peer = request.remote_addr.to_s
    return peer unless loopback_address?(peer)

    forwarded = request.get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").map(&:strip).reject(&:empty?).last
    forwarded.presence || peer
  end

  def loopback_address?(address)
    IPAddr.new(address).loopback?
  rescue IPAddr::Error
    false
  end
end
