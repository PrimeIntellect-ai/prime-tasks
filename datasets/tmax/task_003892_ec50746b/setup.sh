#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages
    apt-get install -y tesseract-ocr imagemagick fonts-liberation gawk

    # Create directories
    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the image fixture
    # We modify ImageMagick policy to allow label generation if needed, but usually label is allowed.
    convert -background white -fill black -font Liberation-Sans -pointsize 36 label:"THRESHOLD: 1625000000" /app/corrupted_threshold.png

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/process_graph_oracle.sh
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
EOF
    chmod +x /opt/oracle/process_graph_oracle.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
