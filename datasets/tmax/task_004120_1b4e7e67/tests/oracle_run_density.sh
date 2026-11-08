#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <fasta_file>"
    exit 1
fi

compute_gc() {
    seq="$1"
    gc=$(echo "$seq" | grep -o -i "[GC]" | wc -l)
    total=$(echo "$seq" | grep -o -i "[ACGT]" | wc -l)
    if [ "$total" -eq 0 ]; then
        echo "0"
    else
        echo "scale=4; $gc / $total" | bc
    fi
}
export -f compute_gc

grep -v "^>" "$1" | xargs -P 4 -I {} bash -c 'compute_gc "{}"'
