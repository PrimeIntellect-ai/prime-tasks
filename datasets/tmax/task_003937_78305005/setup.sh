#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-liberation gawk
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:"INCLUDE ONLY INTERACTION TYPES: ACTIVATES, BINDS" /app/rules.png

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network.tsv
P1	P2	ACTIVATES
P2	P3	BINDS
P3	P4	INHIBITS
P1	P5	BINDS
P5	P4	ACTIVATES
P4	P6	PHOSPHORYLATES
P2	P6	ACTIVATES
P7	P8	BINDS
EOF

    mkdir -p /oracle
    cat << 'EOF' > /oracle/query_oracle.sh
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
EOF
    chmod +x /oracle/query_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
