#!/bin/bash

# Submit CDet jobs using the full GEp replay with GEM tracking and FTROI.
#
# The command-line contract deliberately matches submit-cdet-jobs.sh:
#
#   submit-cdet-gem-jobs.sh RUN NEVENTS FIRST_SEGMENT LAST_SEGMENT RUN_ON_IFARM
#
# Example:
#
#   ./submit-cdet-gem-jobs.sh 5711 100000 0 5 0

set -e

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export CDET_RUN_SCRIPT="${script_dir}/run-cdet-gem-replay.sh"

exec "${script_dir}/submit-cdet-jobs.sh" "$@"
