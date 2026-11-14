#!/bin/sh
# Block public PostgreSQL access even when Docker publishes its container port.
# Internal Docker bridge traffic has a different ingress interface and remains allowed.
set -eu
iface=${1:?public network interface required}
for firewall in iptables ip6tables; do
    for chain in INPUT DOCKER-USER; do
        "$firewall" -w -nL "$chain" >/dev/null
        if ! "$firewall" -w -C "$chain" -i "$iface" -p tcp --dport 5432 -j DROP 2>/dev/null; then
            "$firewall" -w -I "$chain" 1 -i "$iface" -p tcp --dport 5432 -j DROP
            printf 'CHANGED %s %s\n' "$firewall" "$chain"
        fi
    done
done
