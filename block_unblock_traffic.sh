#!/bin/bash

print_help() {
  echo "Usage: $0 --nic <interface> --ip <IP address> --action <block|unblock>"
  echo
  echo "Options:"
  echo "  --nic     Network interface (e.g., eth0)"
  echo "  --ip      IP address to block or unblock"
  echo "  --action  Action to take: block or unblock"
  echo "  --help    Show this help message"
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nic) NIC="$2"; shift ;;
    --ip) IP="$2"; shift ;;
    --action) ACTION="$2"; shift ;;
    --help) print_help ;;
    *) echo "Unknown parameter: $1"; print_help ;;
  esac
  shift
done

# Validate input
if [[ -z "$NIC" || -z "$IP" || -z "$ACTION" ]]; then
  echo "Error: Missing parameters."
  print_help
fi

if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid IP format."
  exit 1
fi

# Perform action
case "$ACTION" in
  block)
    echo "Blocking $IP on $NIC..."
    iptables -A INPUT -i "$NIC" -s "$IP" -j DROP
    ;;
  unblock)
    echo "Unblocking $IP on $NIC..."
    iptables -D INPUT -i "$NIC" -s "$IP" -j DROP
    ;;
  *)
    echo "Error: Invalid action '$ACTION'"
    print_help
    ;;
esac
