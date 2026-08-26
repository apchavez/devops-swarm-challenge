#!/usr/bin/env bash
# Runs build/test/lint inside the same python:3.12 image used by CI, so nothing
# beyond Docker needs to be installed locally. Usage: ./docker/dev.sh <test|lint|shell>
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

IMAGE="python:3.12-slim"
CMD="${1:-test}"
DOCKER_TTY=""
[[ "$CMD" == "shell" ]] && DOCKER_TTY="-it"

run() {
  docker run --rm ${DOCKER_TTY:-} \
    -v "$(pwd -W 2>/dev/null || pwd)":/workspace -w /workspace \
    -v devops-swarm-challenge-venv:/workspace/.venv \
    "$IMAGE" bash -c "$1"
}

case "$CMD" in
  test)
    run "pip install -q -r requirements.txt -r requirements-dev.txt && pytest"
    ;;
  lint)
    run "pip install -q -r requirements-dev.txt && ruff format --check . && ruff check ."
    ;;
  shell) run "bash" ;;
  *) echo "Usage: $0 {test|lint|shell}" >&2; exit 1 ;;
esac
