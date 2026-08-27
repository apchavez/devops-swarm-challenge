#!/usr/bin/env bash
# Deploys the app to a Docker Swarm environment. Simulates DMGR1/DMGR2 in reto.png:
# each swarm manager promotes the same image through DEV -> SIT -> QA.
# Usage: IMAGE=<registry>/devops-swarm-challenge:<tag> ./stack/deploy.sh <dev|sit|qa>
set -euo pipefail
cd "$(dirname "$0")/.."

ENVIRONMENT="${1:?usage: deploy.sh <dev|sit|qa>}"
export IMAGE="${IMAGE:?IMAGE must be set, e.g. IMAGE=trialsvu54e.jfrog.io/docker-trial/devops-swarm-challenge:latest}"

docker stack deploy \
  -c "stack/base.yml" \
  -c "stack/${ENVIRONMENT}.yml" \
  --with-registry-auth \
  "devops-swarm-challenge-${ENVIRONMENT}"
