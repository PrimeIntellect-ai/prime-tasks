Can't connect to Knx gateway behind NAT on VM
I am trying to connect to a knx ip gateway from a homeassistant vm but get a connection error. The vm is behind a NAT on the host.

KNX Gateway IP: 192.168.2.191
Host IP: 192.168.2.249
VM IP: 192.168.1.11

My homeassistant configuration
 <pre>Tunneling:
    Host: '192.168.2.191'
    Port: 3671
    Local_ip: '192.168.1.11'</pre>

Iptables configuration on the host
<pre> echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A PREROUTING -s '192.168.2.191' -j DNAT --to-destination '192.168.1.11'
iptables -t nat -A POSTROUTING -d '192.168.2.191' -j SNAT --to-source '192.168.2.249' </pre>

On tcpdump I see an UDP packet going to Knx gateway but there is no reply packet.

### Additional contract requirements

A KNX/IP tunneling connection used behind NAT must be able to establish a connection by receiving the gateway's replies. The NAT-compatible behavior must be selectable through the application's tunneling configuration using the `route_back` setting. It must apply both to initial connection establishment and to ongoing tunnel control requests.
