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
  $0 --action apply --iface <iface> [--target <ip>] --delay <ms>
  $0 --action clear --iface <iface>

Options:
  --action   apply | clear
             'apply' adds delay to iSCSI traffic (port 3260) to/from a specific IP or entire subnet.
             'clear' removes all tc rules from the given interface.

  --iface    Network interface to apply (e.g., ib0)

  --target   Target IP address (optional for apply). If not given, subnet of --iface will be used.

  --delay    Delay in milliseconds (required for apply)

  --help     Show this help message and exit

Examples:
  $0 --action apply --iface ib0 --target 10.212.12.102 --delay 10
  $0 --action apply --iface ib0 --delay 10
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

# Action: APPLY
if [[ "$ACTION" == "apply" ]]; then
    if [[ -z "$IFACE" || -z "$DELAY_MS" ]]; then
        echo "[ERROR] Missing required arguments for apply."
        print_help
        exit 1
    fi

    # Auto-detect subnet if target IP not provided
    if [[ -z "$TARGET_IP" ]]; then
        echo "[INFO] No --target provided. Detecting subnet of $IFACE..."
        SUBNET=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}')
        if [[ -z "$SUBNET" ]]; then
            echo "[ERROR] Failed to detect subnet for interface $IFACE"
            exit 1
        fi
        echo "[INFO] Using subnet: $SUBNET"
        TARGET_MATCH="$SUBNET"
    else
        TARGET_MATCH="$TARGET_IP/32"
    fi

    echo "[INFO] Resetting qdisc on $IFACE..."
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null

    echo "[INFO] Applying ${DELAY_MS}ms delay to iSCSI (port 3260) traffic matching $TARGET_MATCH on $IFACE"
    sudo tc qdisc add dev "$IFACE" root handle 1: prio
    sudo tc qdisc add dev "$IFACE" parent 1:3 handle 30: netem delay "${DELAY_MS}ms"

    sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 \
        match ip dst "$TARGET_MATCH" match ip dport 3260 0xffff flowid 1:3

    sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 2 u32 \
        match ip src "$TARGET_MATCH" match ip sport 3260 0xffff flowid 1:3

    echo "[DONE] Delay applied."

# Action: CLEAR
elif [[ "$ACTION" == "clear" ]]; then
    if [[ -z "$IFACE" ]]; then
        echo "[ERROR] Missing interface for clear."
        print_help
        exit 1
    fi

    echo "[INFO] Clearing qdisc on $IFACE..."
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null
    echo "[DONE] Delay settings cleared."

# Invalid action
else
    echo "[ERROR] Invalid or missing --action."
    print_help
    exit 1
fi
