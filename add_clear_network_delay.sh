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
  $0 --action show --iface <iface>

Options:
  --action   apply | clear | show
             'apply' adds delay to iSCSI traffic (port 3260) to/from a specific IP or subnet.
             'clear' removes all tc rules from the given interface.
             'show' displays current tc rules on the interface.

  --iface    Network interface to apply (e.g., ib0)

  --target   Target IP address (optional for apply). If not given, subnet of --iface will be used.
             If the detected subnet is /32, it will be expanded to /24.

  --delay    Delay in milliseconds (required for apply)

  --help     Show this help message and exit

Examples:
  $0 --action apply --iface ib0 --target 10.212.12.102 --delay 10
  $0 --action apply --iface ib0 --delay 10
  $0 --action clear --iface ib0
  $0 --action show --iface ib0
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

# ACTION: APPLY
if [[ "$ACTION" == "apply" ]]; then
    if [[ -z "$IFACE" || -z "$DELAY_MS" ]]; then
        echo "[ERROR] Missing required arguments for apply."
        print_help
        exit 1
    fi

    # Auto-detect subnet if target IP not provided
    if [[ -z "$TARGET_IP" ]]; then
        echo "[INFO] No --target provided. Detecting subnet of $IFACE..."
        RAW_SUBNET=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}')
        if [[ -z "$RAW_SUBNET" ]]; then
            echo "[ERROR] Failed to detect subnet for interface $IFACE"
            exit 1
        fi

        IP_ONLY=$(echo "$RAW_SUBNET" | cut -d/ -f1)
        MASK=$(echo "$RAW_SUBNET" | cut -d/ -f2)

        if [[ "$MASK" == "32" ]]; then
            TARGET_MATCH="$(echo "$IP_ONLY" | cut -d. -f1-3).0/24"
            echo "[INFO] Detected /32 mask, using adjusted subnet: $TARGET_MATCH"
        else
            TARGET_MATCH="$RAW_SUBNET"
            echo "[INFO] Using detected subnet: $TARGET_MATCH"
        fi
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

# ACTION: CLEAR
elif [[ "$ACTION" == "clear" ]]; then
    if [[ -z "$IFACE" ]]; then
        echo "[ERROR] Missing interface for clear."
        print_help
        exit 1
    fi

    echo "[INFO] Clearing qdisc on $IFACE..."
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null
    echo "[DONE] Delay settings cleared."

# ACTION: SHOW
elif [[ "$ACTION" == "show" ]]; then
    if [[ -z "$IFACE" ]]; then
        echo "[ERROR] Missing interface for show."
        print_help
        exit 1
    fi

    echo "[INFO] Showing qdisc configuration for $IFACE..."
    sudo tc qdisc show dev "$IFACE"
    echo
    echo "[INFO] Showing filter rules for $IFACE..."
    sudo tc filter show dev "$IFACE"

# INVALID
else
    echo "[ERROR] Invalid or missing --action."
    print_help
    exit 1
fi
