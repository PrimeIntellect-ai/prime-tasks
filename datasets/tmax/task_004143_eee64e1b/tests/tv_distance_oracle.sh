#!/bin/bash
awk -v arg1="$1" -v arg2="$2" '
BEGIN {
    split(arg1, a1, ",");
    split(arg2, a2, ",");
    sum1 = 0; sum2 = 0;
    for (i in a1) sum1 += a1[i];
    for (i in a2) sum2 += a2[i];
    if (sum1 == 0 || sum2 == 0) {
        print "Invalid input";
        exit 1;
    }
    tv = 0;
    for (i in a1) {
        p = a1[i] / sum1;
        q = a2[i] / sum2;
        diff = p - q;
        if (diff < 0) diff = -diff;
        tv += diff;
    }
    printf "%.4f\n", tv / 2;
}'
