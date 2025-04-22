#!/bin/bash

# Function to create the delayed device
create_device() {
    local device="$1"
    echo "Creating delayed device on $device..."
    dmsetup create md0delay --table "0 $(blockdev --getsz $device) delay $device 0 0"
}

# Function to reload the delay values
reload_device() {
    local delay="$1"
    local new_table="0 $(blockdev --getsz /dev/md0) delay /dev/md0 0 $delay"
    echo "Reloading delayed device with new delay value: $delay..."
    echo "$new_table" | dmsetup reload md0delay
    dmsetup resume md0delay
}

# Function to clear the delayed device
clear_device() {
    echo "Removing delayed device md0delay..."
    dmsetup remove md0delay
}

# Function to display help
show_help() {
    echo "Usage: $0 --action <action> [--device <device>] [--delay <delay>]"
    echo
    echo "Actions:"
    echo "  create      Create a delayed device on the specified device."
    echo "  reload      Reload the delay target with a new delay value."
    echo "  clear       Remove the delayed device."
    echo
    echo "Options:"
    echo "  --action <action>   Required. Specify the action to perform (create, reload, or clear)."
    echo "  --device <device>   Required for 'create'. Specify the device to create the delayed device on."
    echo "  --delay <delay>     Required for 'reload'. Specify the new delay value (in milliseconds)."
    echo "  --help              Show this help message."
    echo
}

# Main script
ACTION=""
DEVICE=""
DELAY=""

# Parse command line arguments
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

# Validate action argument
if [[ -z "$ACTION" ]]; then
    echo "Error: --action must be specified."
    show_help
    exit 1
fi

# Perform action based on the argument
case "$ACTION" in
    create)
        if [[ -z "$DEVICE" ]]; then
            echo "Error: --device must be provided for create action."
            exit 1
        fi
        create_device "$DEVICE"
        ;;
    reload)
        if [[ -z "$DELAY" ]]; then
            echo "Error: --delay must be provided for reload action."
            exit 1
        fi
        reload_device "$DELAY"
        ;;
    clear)
        clear_device
        ;;
    *)
        echo "Error: Invalid action. Valid actions are create, reload, or clear."
        show_help
        exit 1
        ;;
esac