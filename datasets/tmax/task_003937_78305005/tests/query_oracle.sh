#!/bin/bash
START=$1
END=$2

if [ "$START" == "$END" ]; then
    echo 0
    exit 0
fi

# Materialize undirected filtered graph
awk '$3 == "ACTIVATES" || $3 == "BINDS" {print $1, $2; print $2, $1}' /home/user/network.tsv | sort | uniq > /tmp/edges.txt

# Simple BFS in bash/awk
echo "$START" > /tmp/visited.txt
echo "$START" > /tmp/frontier.txt
HOPS=0

while [ -s /tmp/frontier.txt ]; do
    HOPS=$((HOPS + 1))

    # Get neighbors of frontier
    awk 'NR==FNR {f[$1]; next} $1 in f {print $2}' /tmp/frontier.txt /tmp/edges.txt | sort | uniq > /tmp/next_frontier_raw.txt

    # Check if end is in next frontier
    if grep -q -x "$END" /tmp/next_frontier_raw.txt; then
        echo $HOPS
        exit 0
    fi

    # Remove already visited
    awk 'NR==FNR {v[$1]; next} !($1 in v) {print $1}' /tmp/visited.txt /tmp/next_frontier_raw.txt > /tmp/frontier.txt

    # Update visited
    cat /tmp/frontier.txt >> /tmp/visited.txt
done

echo "-1"
