# GKE Cluster Node Pool Scaler

This repository contains:
* A containerized Python application that allows to scale GKE Standard cluster node pools. 
* A Helm chart to deploy multiple Kubernetes Cronjobs, one per each schedule (Scale Up and Scale Down), per node pool, per cluster.
* A boostrapping script to create the GCP resoruces necessary to test the application.

## app/gke_node_pool_scaler.py

The script reads a number of environment variables which define what operation will be performed and where:
- A GCP Project ID
- A GCP Location (Region or Zone)
- A GKE Cluster name
- A list of GKE Node Pools, detailing:
  - Their Cluster Autoscaler configuration: Location Policy, Scale Up min and max sizes and Scale Down size.
  - The Schedules for Scale Up and Scale Down operations

### Scale Down mode 

On Scale Down mode, when invoked for a GKE cluster, for each nodepool it will:

- Disable the Cluster Autoscaler
- Scale Down the Node Pool to the desired number of replicas, down to 0 if necessary

### Scale Up mode

On Scale Up mode it will configure the following settings for a node pool:

- Set the location policy to the desired value (Any or Balanced)
- Set the desired number of replicas, setting the min and max values for the corresponding location policy.
- Enable the Cluster Autoscaler with the desired settings, allowing it to scale the nodepool up to the desired value.

### Testing Python Application locally

This application can be run using Python **3.10** or higher.

To scale up pr down a given node pool, configure the enviornment variables and follow the steps to execute the script:
```
export PROJECT_ID=test-project
export LOCATION=us-east1-b
export OPERATION_MODE=SCALE_DOWN
export CLUSTER=cluster-1
export NODEPOOL="node-pool-2|ANY|0|0|1"
export DEBUG=false
export PAUSE_BETWEEN_OPERATIONS=30

# Move into the application directory
cd app/

# Create a Python Virtual Environment
python -m venv poc-venv

# Activate the Virtual Environment
source poc-venv/bin/activate

# Install the requirements
python -m pip install -r <path-to>/requirements.txt

# Make sure you're authenticated against Google Cloud
gcloud auth login

# Run the script
python gke_node_pool_scaler.py
```

## Bootstrapping the Proof of Concept environment

The repository includes a few helper scripts to deploy a Proof-of-Concept environment to test the application.
These are better run from a `Google Cloud Shell` session since it contains all the required tools.

1. `bootstrap.sh` - Will set everything up, and may also build and push the container image to the Artifact Registry repository.

2. `build.sh` - Builds the container image without running the whole bootstrapping process.

3. Once the environment is up and running, and the image has been built, you may deploy the application using Helm as shown in the at the bottom of the page.

### bootstrap.sh

This script will bootstrap a Proof of Concept environment that allows to test this solution with minimal cost. 
In detail, it:

- Creates a GCP project.
- Enables Billing for the project.
- Enables the necessary GCP Services (GKE, Artifact Registry).
- Creates a GCP Service Account (GSA).
- Grants permissions to the GSA.
- Creates and Artifact Registry repository.
- Creates a GKE Cluster with Workload Identity enabled and 4 node pools:
  - default-pool, for system workloads.
  - spot-pool, where the node pool scaling cronjobs will run.
  - node-pool-2 and node-pool-3, to test the scaling operations.
- Create a Kubernetes Service Account in the application namespace.
- Binds the GSA and KSA to leverage Workload Identity.
- Grants permissions to the GSA on the cluster that is to be managed by the Python application.
- Optionally builds and pushes the container image for the node-pool scaler application.

Usage:
```
./bootstrap.sh PROJECT_ID ZONE BILLING_ACCOUNT CLUSTER_NAME APP_NAME REPO_NAME [ --build-and-push-image [TAG] ]
```

Example:
```
./bootstrap.sh test-project us-east1-b A11BB-123ABCD-BCD321 cluster-1 gke-node-pool-scaler testrepo --build-and-push-image 1.0.0
```

### build.sh

If `docker` is installed on your workspace, this script will build and push the container image for the node-pool scaler application.

Usage:
```
./build.sh REPOSITORY_PATH IMAGE_NAME TAG
```

Example:
```
./build.sh us-east1-docker.pkg.dev/test-project/testrepo gke-node-pool-scaler 1.0.0
```

## Helm Chart

The Helm Chart contained in this repository creates as many Kubernetes CronJobs as Node Pool scaling schedules are defined in the VALUES file.

### Rendering the templates

To render the Helm templates locally, from the **root** of this repository, execute the following command:

```
mkdir -p rendered && helm template --debug -f <VALUES-FILE-NAME>.yaml . > rendered/<RENDERED-TEMPLATE-NAME>.yaml
```

### Installing the Chart in the GKE cluster

[Install the Helm CLI](https://helm.sh/docs/intro/install/#from-script) if it is not present on your workspace.

Authenticate against Google Cloud:

```
gcloud auth login
```

Authenticate against the cluster:

```
gcloud container clusters get-credentials CLUSTER_NAME --project PROJECT_ID --location REGION_OR_ZONE
```

To install the release and create the Cronjobs in the selected Namespace, execute the following command from the **root** of this repository:

```
helm install RELEASE_NAME . --namespace NAMESPACE --values <VALUES-FILE-NAME>.yaml
```

To update the release, change any values or edit the templates and execute the following command from the **root** of this repository:

```
helm upgrade RELEASE_NAME . --namespace NAMESPACE --values <VALUES-FILE-NAME>.yaml
```

## Other tools

### gke-node-pool-scaler.sh

This utility script demonstrates how to disable the cluster autoscaler and scale a node pool to a desired number of nodes.