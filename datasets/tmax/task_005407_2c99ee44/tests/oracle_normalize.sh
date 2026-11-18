#!/bin/bash
N=$1
awk -v N="$N" -F, '
BEGIN { OFS="," }
NR==1 { print; next }
NR<=N+1 {
    for(i=1; i<=NF; i++) {
        if (NR==2) { min[i]=$i; max[i]=$i }
        else {
            if ($i < min[i]) min[i]=$i
            if ($i > max[i]) max[i]=$i
        }
    }
    data[NR] = $0
}
NR>N+1 {
    data[NR] = $0
}
END {
    for(r=2; r<=NR; r++) {
        split(data[r], row, ",")
        for(i=1; i<=NF; i++) {
            if (max[i] == min[i]) {
                val = 0.00
            } else {
                val = (row[i] - min[i]) / (max[i] - min[i])
            }
            printf "%.2f%s", val, (i==NF ? "" : OFS)
        }
        print ""
    }
}'
