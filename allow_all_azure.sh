#!/bin/bash

# Function to display usage information
show_usage() {
    echo "Usage: $0 <resource-group>"
    echo "Creates a new rule in the Network Security Group ending with '*internal1-nsg' in the specified resource group."
    echo "Options:"
    echo "  <resource-group>   The name of the Azure resource group."
    echo "  --help             Show this help message."
    exit 0
}

# Check if --help option is provided
if [[ "$1" == "--help" ]]; then
    show_usage
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

create_rule() {
    local rule_name=$1
    local nsg_name=$2
    local resource_group=$3

    az network nsg rule create \
        --name "$rule_name"  \
        --nsg-name "$nsg_name" \
        --resource-group "$resource_group" \
        --priority 199 \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes VirtualNetwork \
        --destination-port-ranges '*' \
        --direction Inbound \
        --source-port-ranges '*' \
        -o tsv

    # Update NSG to ensure the rule is applied immediately
    az network nsg update --name "$nsg_name" --resource-group "$resource_group" -o tsv
}

# Check if resource group parameter is provided
if [ -z "$1" ]; then
    show_usage
fi

# Get the resource group name from the first argument
resource_group=$1

# Get all NSGs in the specified resource group
nsgs=$(az network nsg list --resource-group "$resource_group" --query "[].name" -o tsv)

# Filter NSGs for the one ending with "*internal1-nsg"
for nsg in $nsgs; do
    if [[ "$nsg" == *internal1-nsg ]]; then
        found_nsg=$nsg
        break
    fi
done

# Check if NSG was found
if [ -z "$found_nsg" ]; then
    echo "No Network Security Group ending with '*internal1-nsg' found in resource group '$resource_group'"
else
    echo "The Network Security Group ending with '*internal1-nsg' in resource group '$resource_group' is: $found_nsg"
    echo "Creating a new rule in NSG '$found_nsg'..."
    create_rule "new-rule" "$found_nsg" "$resource_group"
    echo "New rule created successfully."
fi

# Add counter to wait for 20 seconds
echo "Waiting for 20 seconds..."
sleep 20
echo "We are done."

