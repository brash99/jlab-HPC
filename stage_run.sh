#!/bin/bash
# stage_run.sh — pre-stage EVIO files for a given run into /cache
# Usage:
#   ./stage_run.sh <runnum>             # stage ALL segments & streams for this run
#   ./stage_run.sh <runnum> <segment>   # stage ONLY that segment (all streams)
#   ./stage_run.sh <runnum> <start>-<end>  # stage a RANGE of segments (inclusive)

runnum=$1
segment=$2

if [[ -z "$runnum" ]]; then
  echo "Usage:"
  echo "  $0 <runnum>             # stage ALL segments"
  echo "  $0 <runnum> <segment>   # stage one segment"
  echo "  $0 <runnum> <start>-<end>  # stage a range of segments"
  exit 1
fi

stage_segment() {
  local run=$1
  local seg=$2
  for f in /mss/halla/sbs/GEp/raw/gep5_${run}.evio.*.${seg}; do
    if [[ -f "$f" ]]; then
      echo "Staging $f"
      jcache get "$f"
    else
      echo "Warning: $f not found in MSS"
    fi
  done
}

if [[ -z "$segment" ]]; then
  # Stage ALL segments & streams
  for f in /mss/halla/sbs/GEp/raw/gep5_${runnum}.evio.*; do
    echo "Staging $f"
    jcache get "$f"
  done
elif [[ "$segment" =~ ^[0-9]+$ ]]; then
  # Single segment
  stage_segment $runnum $segment
elif [[ "$segment" =~ ^[0-9]+-[0-9]+$ ]]; then
  # Range of segments
  start=${segment%-*}
  end=${segment#*-}
  for ((i=start; i<=end; i++)); do
    stage_segment $runnum $i
  done
else
  echo "Invalid segment argument: $segment"
  exit 1
fi
