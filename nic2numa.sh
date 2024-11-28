#!/bin/bash
echo -e "Interface\tNUMA_Node"

# Loop through all network interfaces
for iface in $(ls /sys/class/net | grep -v lo); do
    # Get the NUMA node serving the interface
    numa_node=$(cat /sys/class/net/$iface/device/numa_node 2>/dev/null || echo "N/A")

    # Print the interface and its NUMA node
    echo -e "$iface\t$numa_node"
done
