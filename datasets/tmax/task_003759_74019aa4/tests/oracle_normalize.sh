#!/bin/bash
awk -v lambda=12 '
{
    for(i=1; i<=NF; i++) {
        a[NR,i] = $i
        rowsum[NR] += $i
    }
    cols = NF
}
END {
    for(i=1; i<=NR; i++) {
        for(j=1; j<=cols; j++) {
            if (i==j) {
                val = rowsum[i] - a[i,j] + lambda
            } else {
                val = -a[i,j]
            }
            printf "%s%s", val, (j==cols ? "" : " ")
        }
        print ""
    }
}'
