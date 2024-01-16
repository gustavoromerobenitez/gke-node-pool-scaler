#!/bin/bash

#
# This simple utility script disables the cluster autoscaler for a nodepool
# and resizes the nodepool manually to the desired number of nodes
#

if [[ $# -lt 5 ]]; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] Usage: $0 CLUSTER NODEPOOL SIZE LOCATION PROJECT"
  echo >&2 "[FATAL]"
  exit 1
fi

if ! which gcloud >/dev/null; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] Gcloud SDK is required to run this script."
  echo >&2 "[FATAL]"
  exit 2
fi


CLUSTER=$1
NODEPOOL=$2
SIZE=$3
LOCATION=$4
PROJECT=$5

echo "[INFO]"
echo "[INFO] Disabling the Cluster Autoscaler for Node Pool ${NODEPOOL} on Cluster ${CLUSTER}..."
echo "[INFO]"
gcloud container clusters update ${CLUSTER} \
  --node-pool=${NODEPOOL} \
  --no-enable-autoscaling \
  --location=${LOCATION} \
  --project=${PROJECT}

if [[ $? -ne 0 ]]; then
  echo >&2 "[ERROR]"
  echo >&2 "[ERROR] Failed to disable the Cluster Autoscaler on Node Pool ${NODEPOOL}"
  echo >&2 "[ERROR]"
  exit 3
fi

# After disabling the cluster autoscaler for a node pool it is advisable to wait for a few seconds for the change to be effective.
# If the autoscaler is not disabled or the change has not taken effect, the next resize command might not work
echo "[INFO]"
echo "[INFO] Waiting 30 seconds to allow the Cluster Autoscaler change to take effect..."
echo "[INFO]"
sleep 30

echo "[INFO]"
echo "[INFO] Scaling the Node Pool ${NODEPOOL} to ${SIZE} nodes..."
echo "[INFO]"
gcloud container clusters resize ${CLUSTER} \
  --node-pool=${NODEPOOL} \
  --num-nodes=${SIZE} \
  --location=${LOCATION} \
  --project=${PROJECT} \
  --quiet

if [[ $? -ne 0 ]]; then
  echo >&2 "[ERROR]"
  echo >&2 "[ERROR] Failed to resize the Node Pool ${NODEPOOL} on Cluster ${CLUSTER}"
  echo >&2 "[ERROR]"
  exit 4
fi

exit 0