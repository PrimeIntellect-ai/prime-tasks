#!/bin/bash
export PATH="/home/user/local/bin:$PATH"

awk -F',' '{
    bucket = int($1 / 60000) * 60000;
    print bucket "," 1 "," $2;
    print bucket "," 2 "," $3;
    print bucket "," 3 "," $4;
}' | \
sort -t',' -k1,1n -k2,2n | \
datamash -t',' groupby 1,2 mean 3 | \
awk -F',' '{ printf "%s,%s,%.2f\n", $1, $2, $3 }'
