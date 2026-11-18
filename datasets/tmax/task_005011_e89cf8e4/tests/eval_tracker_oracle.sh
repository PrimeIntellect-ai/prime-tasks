#!/bin/bash
awk -F',' '$5 != "" {
    exp=$2;
    time_sum[exp]+=$3;
    count[exp]++;
    if($4==$5) correct[exp]++;
}
END {
    for (e in count) {
        avg_time = time_sum[e] / count[e];
        acc = correct[e] / count[e];
        printf "%s,%.4f,%.4f\n", e, avg_time, acc;
    }
}' "$1" | sort -t',' -k1,1
