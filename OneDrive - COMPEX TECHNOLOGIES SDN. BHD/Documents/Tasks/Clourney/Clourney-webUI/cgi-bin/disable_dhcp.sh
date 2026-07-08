#! /bin/sh

echo "Content-type: text/plain"
echo ""

uci set dhcp.lan.ignore=1
uci set dhcp.lan.dhcpv4=disabled
uci set dhcp.lan.dhcpv6=disabled
uci del dhcp.lan.start
uci del dhcp.lan.limit
uci del dhcp.lan.leasetime
uci commit dhcp

( sleep 2; /etc/inid.d/dnsmasq restart; /etc/init.d/odhcpd restart ) &

echo "SUCCESS"