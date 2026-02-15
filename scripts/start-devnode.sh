#!/usr/bin/env bash
# Start Arbitrum Nitro devnode so RPC is available at http://localhost:8547
# Prerequisites: Docker running, jq, cast (Foundry)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NITRO_DEVNODE="${NITRO_DEVNODE:-$SCRIPT_DIR/../../nitro-devnode}"
if [[ ! -x "$NITRO_DEVNODE/run-dev-node.sh" ]]; then
  echo "Run from repo root: git clone https://github.com/OffchainLabs/nitro-devnode.git ../nitro-devnode"
  echo "Then: cd ../nitro-devnode && ./run-dev-node.sh"
  exit 1
fi
exec "$NITRO_DEVNODE/run-dev-node.sh" "$@"
