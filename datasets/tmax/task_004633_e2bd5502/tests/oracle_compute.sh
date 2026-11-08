#!/bin/bash
awk '
/^>/ { next }
NF == 2 {
    t = $1; y = $2;
    if (NR > 2) {
        area += (t - prev_t) * (y + prev_y) / 2.0;
    }
    prev_t = t; prev_y = y;
}
END {
    printf "%.4f\n", area;
}' "$1"
