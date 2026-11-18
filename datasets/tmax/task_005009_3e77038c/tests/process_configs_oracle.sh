#!/bin/bash
# Oracle script implementing the exact sliding window logic
window=()
while read -r line; do
    # Simple regex extraction acting as the "fixed" parser
    if echo "$line" | grep -q '"metric": *"memory_weight"'; then
        val=$(echo "$line" | sed -n 's/.*"value": *\([0-9]*\).*/\1/p')
        if [ -n "$val" ]; then
            window+=("$val")
            if [ ${#window[@]} -gt 5 ]; then
                window=("${window[@]:1:5}")
            fi
            sum=0
            for v in "${window[@]}"; do
                sum=$((sum + v))
            done
            avg=$((sum / ${#window[@]}))
            echo "$avg"
        fi
    fi
done
