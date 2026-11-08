#!/bin/bash
awk -F',' '$1 % 10 == 0 { sum[$2]+=$3; count[$2]++ } END { for (s in sum) print s "," sum[s] "," count[s] }' | sort -t',' -k1,1
