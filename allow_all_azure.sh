#!/bin/bash

# Function to display usage information
show_usage() {
    echo "Usage: $0 [-c|-d] <resource-group>"
    echo "Creates or deletes a rule named 'qperf' in the Network Security Group ending with '*internal1-nsg' in the specified resource group."
    echo "Options:"
    echo "  -c                 Create the rule 'qperf'."
    echo "  -d                 Delete the rule 'qperf'."
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

# Function to create a new rule in the specified NSG
create_rule() {
    local rule_name="qperf"
    local nsg_name=$1
    local resource_group=$2

    az network nsg rule create \
        --name "$rule_name" \
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

# Function to delete the rule in the specified NSG
delete_rule() {
    local rule_name="qperf"
    local nsg_name=$1
    local resource_group=$2

    az network nsg rule delete \
        --name "$rule_name" \
        --nsg-name "$nsg_name" \
        --resource-group "$resource_group" \
        -o tsv

    # Update NSG to ensure the rule is removed immediately
    az network nsg update --name "$nsg_name" --resource-group "$resource_group" -o tsv
}

# Check if action parameter is provided
if [ -z "$1" ] || [ -z "$2" ]; then
    show_usage
fi

# Get the action parameter
action=$1
shift

# Get the resource group name from the remaining argument
resource_group=$1

# Get all NSGs in the specified resource group
nsgs=$(az network nsg list --resource-group "$resource_group" --query "[].name" -o tsv)

# Filter NSGs for the one ending with "*internal1-nsg"
found_nsg=""
for nsg in $nsgs; do
    if [[ "$nsg" == *internal1-nsg ]]; then
        found_nsg=$nsg
        break
    fi
done

# Check if NSG was found
if [ -z "$found_nsg" ]; then
    echo "No Network Security Group ending with '*internal1-nsg' found in resource group '$resource_group'"
    exit 1
else
    echo "The Network Security Group ending with '*internal1-nsg' in resource group '$resource_group' is: $found_nsg"
    if [[ "$action" == "-c" ]]; then
        echo "Creating a new rule 'qperf' in NSG '$found_nsg'..."
        create_rule "$found_nsg" "$resource_group"
        echo "New rule 'qperf' created successfully."
    elif [[ "$action" == "-d" ]]; then
        echo "Deleting the rule 'qperf' in NSG '$found_nsg'..."
        delete_rule "$found_nsg" "$resource_group"
        echo "Rule 'qperf' deleted successfully."
    else
        show_usage
    fi
fi

# Wait for 20 seconds if creating a rule
if [[ "$action" == "-c" ]]; then
    echo "Waiting for 20 seconds..."
    sleep 20
    echo "We are done."
fi

