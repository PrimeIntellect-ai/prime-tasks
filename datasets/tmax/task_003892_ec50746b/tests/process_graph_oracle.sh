#!/bin/bash
awk -F',' '
{
    src = $1
    tgt = $2
    ts = $3

    if (src != tgt && ts >= 1625000000) {
        idx = src "," tgt
        if (!(idx in max_ts) || ts > max_ts[idx]) {
            max_ts[idx] = ts
        }
    }
}
END {
    for (idx in max_ts) {
        split(idx, nodes, ",")
        printf "CREATE (n%s)-[:CONNECTED_TO {time: %s}]->(n%s);\n", nodes[1], max_ts[idx], nodes[2]
    }
}' | sort
