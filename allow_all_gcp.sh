#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0 [-c | -d] --projectname <project-name> --cluster_id <cluster-id>"
  exit 1
}

# Variables
ACTION=""
PROJECT=""
CLUSTER_ID=""
RULE_NAME="qpef"
DIRECTION="INGRESS"
PRIORITY=999
FIREWALL_ACTION="ALLOW"
RULES="all"
SOURCE_RANGES="0.0.0.0/0"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -c) ACTION="create"; shift ;;
    -d) ACTION="delete"; shift ;;
    --projectname) PROJECT="$2"; shift 2 ;;
    --cluster_id) CLUSTER_ID="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Check if the action, project name, and cluster ID are provided
if [ -z "$ACTION" ] || [ -z "$PROJECT" ] || [ -z "$CLUSTER_ID" ]; then
  usage
fi

# Compose the NETWORK variable
NETWORK="flex-cluster-$CLUSTER_ID-network-internal1"

# Function to create firewall rule
create_firewall_rule() {
  gcloud compute --project=$PROJECT firewall-rules create $RULE_NAME \
    --direction=$DIRECTION \
    --priority=$PRIORITY \
    --network=$NETWORK \
    --action=$FIREWALL_ACTION \
    --rules=$RULES \
    --source-ranges=$SOURCE_RANGES

  if [ $? -eq 0 ]; then
    echo "Firewall rule $RULE_NAME created successfully in project $PROJECT."
  else
    echo "Failed to create firewall rule $RULE_NAME in project $PROJECT."
  fi
}

# Function to delete firewall rule
delete_firewall_rule() {
  gcloud compute --project=$PROJECT firewall-rules delete $RULE_NAME --quiet

  if [ $? -eq 0 ]; then
    echo "Firewall rule $RULE_NAME deleted successfully in project $PROJECT."
  else
    echo "Failed to delete firewall rule $RULE_NAME in project $PROJECT."
  fi
}

# Perform the action
case $ACTION in
  create) create_firewall_rule ;;
  delete) delete_firewall_rule ;;
  *) usage ;;
esac

