#!/bin/bash -e

if [[ $# -lt 3 ]]; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] Usage: $0 REGISTRY IMAGE_PATH TAG"
  echo >&2 "[FATAL]"
  exit 1
fi

if ! which docker >/dev/null; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] docker is required to run this script."
  echo >&2 "[FATAL]"
  exit 2
fi

if ! which jq >/dev/null; then
  echo >&2 "[FATAL]"
  echo >&2 "[FATAL] jq is required to run this script."
  echo >&2 "[FATAL]"
  exit 2
fi

REGISTRY=$1
IMAGE_PATH=$2
TAG=$3

# Build the image
docker build -t ${REGISTRY}/${IMAGE_PATH}:${TAG} .

# Retrieve the DIGEST and print it out
DIGEST=$(docker image ls --digests --format json ${REGISTRY}/${IMAGE_PATH} | grep -e "\"${TAG}\"" | jq -r .Digest)

# Push to the remote repository
docker push ${REGISTRY}/${IMAGE_PATH}:${TAG}

echo "[INFO] =============================================================================================================================="
echo "[INFO] Image ${REGISTRY}/${IMAGE_PATH}:${TAG} built successfully."
echo "[INFO]   Digest: ${DIGEST}"
echo "[INFO] =============================================================================================================================="

exit 0