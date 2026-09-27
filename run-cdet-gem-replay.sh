#!/bin/bash

# Parallel runner for CDet studies that require the full GEp detector setup.
# The implementation remains in run-cdet-replay.sh; this entry point selects
# replay_gep.C with dogems=1, which instantiates gemFT, gemFPP, and FTROI.

set -e

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export CDET_ENABLE_GEMS=1

exec "${script_dir}/run-cdet-replay.sh" "$@"
