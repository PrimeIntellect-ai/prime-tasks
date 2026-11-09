#!/bin/bash
# T is exactly 12 based on the 12 frames in the video
T=12
awk '{print $1, $2}' "$1" | sort -u | awk '{count[$1]++} END {for (node in count) if (count[node] > '"$T"') print node, count[node]}' | sort -k2,2nr -k1,1
