#!/bin/bash -e

#
# For the sake of simplicity, this script assumes that the GKE cluster, 
#  Artifact Registry repository and GCP Service Account coexist in the same project
#

#
# EXAMPLES:  ./bootstrap.sh test-project us-east1-b 123AB-DEF345-234BFG cluster-1 gke-node-pool-scaler testrepo
#


if [[ $# -lt 6 ]]; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] Usage: $0 PROJECT_ID ZONE BILLING_ACCOUNT CLUSTER_NAME APP_NAME REPO_NAME [ --build-and-push-image [TAG] ]"
  echo >&2 "[FATAL]"
  exit 1
fi

if ! which gcloud >/dev/null; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] gcloud is required to run this script."
  echo >&2 "[FATAL]"
  exit 2
fi

if ! which kubectl >/dev/null; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] kubectl is required to run this script."
  echo >&2 "[FATAL]"
  exit 2
fi

PROJECT_ID=$1
ZONE=$2
REGION=${ZONE%%-[a-z]}
BILLING_ACCOUNT=$3
CLUSTER_NAME=$4
APP_NAME=$5
REPO_NAME=$6

BUILD_AND_PUSH="NO"
TAG="1.0.0"
if [[ $# -ge 7 ]]; then
  
  if [[ "$7" == "--build-and-push-image" ]]; then
    
    BUILD_AND_PUSH="YES"

    if [[ $# -eq 8 ]]; then

      TAG=$8

    fi

  else

    echo >&2 "[FATAL]"
    echo >&2 "[FATAL] Usage: $0 PROJECT_ID ZONE BILLING_ACCOUNT CLUSTER_NAME APP_NAME REPO_NAME [ --build-and-push-image [TAG] ]"
    echo >&2 "[FATAL]"
    exit 1

  fi

fi

GCP_SA_NAME=$APP_NAME
KSA_NAME=$APP_NAME
NAMESPACE=$APP_NAME
IMAGE_NAME=$APP_NAME

# Create the Project
if ! gcloud projects list --format="value(NAME)" | grep -e "^${PROJECT_ID}$" >/dev/null; then
  
  echo "[INFO] Creating Project ${PROJECT_ID}..."
  gcloud projects create "${PROJECT_ID}" 2>/dev/null
  sleep 30

fi

# Enable billing the new project
if ! gcloud billing projects list --billing-account="${BILLING_ACCOUNT}" --format="value(PROJECT_ID)" | grep -e "^${PROJECT_ID}$" >/dev/null; then
  
  echo "[INFO] Enabling Billing for the new project..."
  gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
  sleep 30

fi

for api in iam.googleapis.com container.googleapis.com artifactregistry.googleapis.com; do
  if ! gcloud services --project "${PROJECT_ID}" list --enabled  | grep "${api}" >/dev/null; then
    
    echo "[INFO] Enabling API: ${api}..."
    gcloud services --project "${PROJECT_ID}" enable "${api}"
    sleep 30

  fi
done

##########################################################################
#
# Create a GKE cluster with Workload Identity enabled and 3 node pools:
# - The default node pool will run the GKE system workloads
# - The spot-pool will use SpotVMs and run the Cronjobs
# - The other node pools will be use to test the application
#

if ! gcloud container clusters list --format="value(NAME)" --project="${PROJECT_ID}" | grep "${CLUSTER_NAME}" >/dev/null; then

  echo "[INFO] Creating cluster with default node pool for system workloads..."
  gcloud container --project "${PROJECT_ID}" clusters create "${CLUSTER_NAME}" \
      --num-nodes=1 \
      --enable-cost-allocation \
      --enable-image-streaming \
      --cluster-dns=clouddns \
      --workload-pool=${PROJECT_ID}.svc.id.goog \
      --zone "${ZONE}" \
      --no-enable-basic-auth \
      --cluster-version "1.27.3-gke.100" \
      --release-channel "regular" \
      --machine-type "e2-highcpu-2" \
      --image-type "COS_CONTAINERD" \
      --disk-type "pd-standard" \
      --disk-size "10" \
      --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --enable-autoscaling \
      --location-policy=ANY \
      --total-max-nodes=1 \
      --total-min-nodes=0 \
      --enable-ip-alias \
      --network "projects/${PROJECT_ID}/global/networks/default" \
      --subnetwork "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default" \
      --no-enable-intra-node-visibility \
      --default-max-pods-per-node "110" \
      --security-posture=standard \
      --workload-vulnerability-scanning=disabled \
      --no-enable-master-authorized-networks \
      --enable-autoupgrade \
      --enable-autorepair \
      --max-surge-upgrade 1 \
      --max-unavailable-upgrade 0 \
      --binauthz-evaluation-mode=DISABLED \
      --no-enable-managed-prometheus \
      --enable-shielded-nodes \
      --node-locations "${ZONE}" \
      --node-taints "components.gke.io/gke-managed-components=true:NoSchedule" \
      --node-labels "workloadType=system"

fi 


if ! gcloud container node-pools list --cluster ${CLUSTER_NAME} --zone ${ZONE} --format="value(NAME)" --project="${PROJECT_ID}" | grep "node-pool-2" > /dev/null; then

  echo "[INFO] Creating node-pool-2..."
  gcloud container --project "${PROJECT_ID}" node-pools create "node-pool-2" \
      --cluster "${CLUSTER_NAME}" \
      --zone "${ZONE}" \
      --machine-type "e2-micro" \
      --image-type "COS_CONTAINERD" \
      --disk-type "pd-standard" \
      --disk-size "10" \
      --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" \
      --enable-autoscaling \
      --total-min-nodes "0" \
      --total-max-nodes "1" \
      --location-policy "ANY" \
      --enable-autoupgrade \
      --enable-autorepair \
      --max-surge-upgrade 1 \
      --max-unavailable-upgrade 0 \
      --node-locations "${ZONE}" \
      --node-taints "workloadType=user:NoSchedule" \
      --node-labels "workloadType=user"
    
fi


if ! gcloud container node-pools list --cluster ${CLUSTER_NAME} --zone ${ZONE} --format="value(NAME)" --project="${PROJECT_ID}" | grep "node-pool-3" > /dev/null; then

  echo "[INFO] Creating node-pool-3..."
  gcloud container --project "${PROJECT_ID}" node-pools create "node-pool-3" \
      --cluster "${CLUSTER_NAME}" \
      --zone "${ZONE}" \
      --machine-type "e2-micro" \
      --image-type "COS_CONTAINERD" \
      --disk-type "pd-standard" \
      --disk-size "10" \
      --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" \
      --enable-autoscaling \
      --total-min-nodes "0" \
      --total-max-nodes "1" \
      --location-policy "ANY" \
      --enable-autoupgrade \
      --enable-autorepair \
      --max-surge-upgrade 1 \
      --max-unavailable-upgrade 0 \
      --node-locations "${ZONE}" \
      --node-taints "workloadType=user:NoSchedule" \
      --node-labels "workloadType=user"

fi


if ! gcloud container node-pools list --cluster ${CLUSTER_NAME} --zone ${ZONE} --format="value(NAME)" --project="${PROJECT_ID}" | grep "spot-pool" > /dev/null; then

  echo "[INFO] Creating spot-pool to run the CronJobs..."
  gcloud container --project "${PROJECT_ID}" node-pools create "spot-pool" \
      --cluster "${CLUSTER_NAME}" \
      --zone "${ZONE}" \
      --spot \
      --machine-type "e2-micro" \
      --image-type "COS_CONTAINERD" \
      --disk-type "pd-standard" \
      --disk-size "10" \
      --metadata disable-legacy-endpoints=true \
      --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes "1" \
      --enable-autoscaling \
      --total-min-nodes "0" \
      --total-max-nodes "1" \
      --location-policy "ANY" \
      --enable-autoupgrade \
      --enable-autorepair \
      --max-surge-upgrade 1 \
      --max-unavailable-upgrade 0 \
      --node-locations "${ZONE}" \
      --node-taints "workloadType=user:NoSchedule" \
      --node-labels "workloadType=user"

fi

echo "[INFO] Authenticating against the cluster..."
gcloud container clusters get-credentials ${CLUSTER_NAME} --project=${PROJECT_ID} --location=${ZONE}


if ! kubectl get namespace "${NAMESPACE}"; then

  echo "[INFO] Creating the Kubernetes Namespace for the application..."
  kubectl create namespace "${NAMESPACE}"

fi


if ! kubectl get serviceaccount "${KSA_NAME}" --namespace "${NAMESPACE}"; then
  
  echo "[INFO] Creating the Kubernetes Service Account for the application..."
  kubectl create serviceaccount "${KSA_NAME}" --namespace "${NAMESPACE}"

  echo "[INFO] Annotating the Service Account to configure Workload Identity..."
  kubectl annotate serviceaccount "${KSA_NAME}" --namespace "${NAMESPACE}" \
        iam.gke.io/gcp-service-account=${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

fi


if ! gcloud artifacts repositories list --location="${REGION}" --project="${PROJECT_ID}" --format="value(REPOSITORY)" 2>/dev/null | grep "${REPO_NAME}" >/dev/null; then
  
  echo "[INFO] Creating the Artifact Registry repository..."
  gcloud artifacts repositories create "${REPO_NAME}" \
      --repository-format=docker \
      --location="${REGION}" \
      --description="Default repository for containers" \
      --immutable-tags \
      --project="${PROJECT_ID}"      

fi


if ! gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(NAME)" | grep "${GCP_SA_NAME}" >/dev/null; then
  
  echo "[INFO] Creating the Google Service Account..."
  gcloud iam service-accounts create ${GCP_SA_NAME} --project=${PROJECT_ID}

fi 


echo "[INFO] Granting Artifact Registry reader permissions to the Google Service Account..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/artifactregistry.reader"


echo "[INFO] Binding the Google Service Account and the Kubernetes Service Account..."
gcloud iam service-accounts add-iam-policy-binding "${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --project="${PROJECT_ID}"

echo "[INFO] Granting Cluster Admin permissions on the cluster that is to be managed."
echo "[INFO]   This is a pre-requisite for any cluster to be managed by the application."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --role roles/container.clusterAdmin \
    --member "serviceAccount:${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \

if [[ "$BUILD_AND_PUSH" == "YES" ]]; then

  echo "[INFO] Building and pushing the container image (TAG: ${TAG})."
  ./build.sh ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME} ${IMAGE_NAME} ${TAG}

fi

echo "[INFO] ====================================="
echo "[INFO] Bootstrapping completed successfully."
echo "[INFO] ====================================="

exit 0
