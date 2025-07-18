#!/bin/bash
#test
print_help() {
  echo "Usage: $0 --nic <interface> --ip <IP address> --action <block|unblock>"
  echo
  echo "Options:"
  echo "  --nic     Network interface (e.g., eth0, eth6)"
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
  echo "Error: Missing required parameters."
  print_help
fi

if ! [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Error: Invalid IP format: $IP"
  exit 1
fi

# Perform action
case "$ACTION" in
  block)
    echo "Blocking IP $IP on interface $NIC..."
    iptables -I INPUT   -i "$NIC" -s "$IP" -j DROP
    iptables -I FORWARD -i "$NIC" -s "$IP" -j DROP
    iptables -I OUTPUT  -o "$NIC" -d "$IP" -j DROP
    ;;
  unblock)
    echo "Unblocking IP $IP on interface $NIC..."
    iptables -D INPUT   -i "$NIC" -s "$IP" -j DROP
    iptables -D FORWARD -i "$NIC" -s "$IP" -j DROP
    iptables -D OUTPUT  -o "$NIC" -d "$IP" -j DROP
    ;;
  *)
    echo "Error: Unknown action '$ACTION'. Use 'block' or 'unblock'."
    print_help
    ;;
esac
