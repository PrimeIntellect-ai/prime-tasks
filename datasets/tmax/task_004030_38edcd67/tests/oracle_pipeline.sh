#!/bin/bash
IFS=',' read -r id col2 col3 <<< "$1"

if [ -z "$col2" ] || [ "$col2" == "NaN" ]; then
    col2=15.5
fi

is_outlier=$(echo "$col3 > 100.0" | bc)
if [ "$is_outlier" -eq 1 ]; then
    col3=100.0
fi

score=$(echo "scale=4; ($col2 * 0.4) + ($col3 * 0.6)" | bc)
printf "%s,%s,%s,%.2f\n" "$id" "$col2" "$col3" "$score"
