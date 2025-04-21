#!/bin/bash

# Default values
ACTION=""
IFACE=""
TARGET_IP=""
DELAY_MS=""

# Help message
print_help() {
cat << EOF
Usage:
  $0 --action apply --iface <iface> --target <ip> --delay <ms>
  $0 --action clear --iface <iface>

Options:
  --action   apply | clear
             'apply' adds delay to iSCSI traffic to/from a specific IP.
             'clear' removes all tc rules from the given interface.

  --iface    Network interface to apply (e.g., ib0)

  --target   Target IP address (required for apply)

  --delay    Delay in milliseconds (required for apply)

  --help     Show this help message and exit

Examples:
  $0 --action apply --iface ib0 --target 10.212.12.102 --delay 10
  $0 --action clear --iface ib0
EOF
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --action) ACTION="$2"; shift ;;
        --iface) IFACE="$2"; shift ;;
        --target) TARGET_IP="$2"; shift ;;
        --delay) DELAY_MS="$2"; shift ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "[ERROR] Unknown parameter: $1"; print_help; exit 1 ;;
    esac
    shift
done

# Core logic (unchanged)
if [[ "$ACTION" == "apply" ]]; then
    if [[ -z "$IFACE" || -z "$TARGET_IP" || -z "$DELAY_MS" ]]; then
        echo "[ERROR] Missing required arguments for apply."
        print_help
        exit 1
    fi

    echo "[INFO] Resetting qdisc on $IFACE..."
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null

    echo "[INFO] Applying ${DELAY_MS}ms delay for iSCSI traffic to/from $TARGET_IP on $IFACE"
    sudo tc qdisc add dev "$IFACE" root handle 1: prio
    sudo tc qdisc add dev "$IFACE" parent 1:3 handle 30: netem delay "${DELAY_MS}ms"

    sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 \
        match ip dst "$TARGET_IP"/32 match ip dport 3260 0xffff flowid 1:3

    sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 2 u32 \
        match ip src "$TARGET_IP"/32 match ip sport 3260 0xffff flowid 1:3

    echo "[DONE] Delay applied."

elif [[ "$ACTION" == "clear" ]]; then
    if [[ -z "$IFACE" ]]; then
        echo "[ERROR] Missing interface for clear."
        print_help
        exit 1
    fi

    echo "[INFO] Clearing qdisc on $IFACE..."
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null
    echo "[DONE] Delay settings cleared."

else
    echo "[ERROR] Invalid or missing --action."
    print_help
    exit 1
fi
