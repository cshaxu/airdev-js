#!/bin/bash

# Validate input arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <root-path> [depth]"
    exit 1
fi

root_path="$1"
depth="$2"

if [ -d "$root_path" ]; then
  current_depth=0
  while [ "$current_depth" -le "$depth" ]; do
    # List directories only at the current depth
    dirs=$(find "$root_path" -mindepth "$current_depth" -maxdepth "$current_depth" -type d)
   
    for dir in $dirs; do
      lines=$(find "$dir" -type f -name '*.*' -exec wc -l {} + | awk '{sum += $1} END {print sum}')
      echo -e "$lines\t$dir"
    done
    ((current_depth++))
  done
else
  lines=$(wc -l package.json | awk '{sum += $1} END {print sum}')
  echo -e "$lines\t$root_path"
fi
