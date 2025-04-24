#!/bin/bash

# Function to derive the delayed device name
get_delayed_name() {
    local device="$1"
    basename=$(basename "$device")
    echo "${basename}_delayed"
}

# Create delayed device
create_device() {
    local device="$1"
    local name=$(get_delayed_name "$device")
    echo "Creating delayed device /dev/mapper/$name on $device..."
    dmsetup create "$name" --table "0 $(blockdev --getsz $device) delay $device 0 0"
}

# Reload delay settings
reload_device() {
    local device="$1"
    local delay="$2"
    local name=$(get_delayed_name "$device")
    local new_table="0 $(blockdev --getsz $device) delay $device 0 $delay"
    echo "Reloading delayed device /dev/mapper/$name with delay $delay..."
    echo "$new_table" | dmsetup reload "$name"
    dmsetup resume "$name"
}

# Remove delayed device
clear_device() {
    local device="$1"
    local name=$(get_delayed_name "$device")
    echo "Removing delayed device /dev/mapper/$name..."
    dmsetup remove "$name"
}

# Show config for a specific delayed device
show_device() {
    local device="$1"
    local name=$(get_delayed_name "$device")
    echo "Configuration for /dev/mapper/$name:"
    dmsetup table "$name"
}

# List all *_delayed devices
list_devices() {
    echo "Listing all *_delayed devices:"
    for name in /dev/mapper/*_delayed; do
        [[ -e "$name" ]] || continue
        echo "Device: $name"
        dmsetup table "$(basename "$name")"
        echo
    done
}

# Help text
show_help() {
    echo "Usage: $0 --action <action> [--device <device>] [--delay <delay>]"
    echo
    echo "Actions:"
    echo "  create      Create a delayed device on the specified device."
    echo "  reload      Reload the delay target with a new delay value."
    echo "  clear       Remove the delayed device."
    echo "  show        Show configuration of a specific delayed device."
    echo "  list        List all current *_delayed device configurations."
    echo
    echo "Options:"
    echo "  --action <action>   Required. Action to perform."
    echo "  --device <device>   Required for create, reload, clear, show."
    echo "  --delay <delay>     Required for reload. Delay value in ms."
    echo "  --help              Show this help."
    echo
}

# Main logic
ACTION=""
DEVICE=""
DELAY=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --delay)
            DELAY="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ACTION" ]]; then
    echo "Error: --action must be specified."
    show_help
    exit 1
fi

if [[ "$ACTION" =~ ^(create|reload|clear|show)$ && -z "$DEVICE" ]]; then
    echo "Error: --device must be specified for '$ACTION'."
    exit 1
fi

# Execute action
case "$ACTION" in
    create)
        create_device "$DEVICE"
        ;;
    reload)
        if [[ -z "$DELAY" ]]; then
            echo "Error: --delay must be provided for reload action."
            exit 1
        fi
        reload_device "$DEVICE" "$DELAY"
        ;;
    clear)
        clear_device "$DEVICE"
        ;;
    show)
        show_device "$DEVICE"
        ;;
    list)
        list_devices
        ;;
    *)
        echo "Invalid action: $ACTION"
        show_help
        exit 1
        ;;
esac
