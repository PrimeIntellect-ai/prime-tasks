#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cargo \
        rustc \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the oracle as a Python script
    cat << 'EOF' > /app/oracle_relevance_calc
#!/usr/bin/env python3
import sys
import json

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    nodes = data.get("nodes", [])
    edges = data.get("edges", [])

    in_deg = {}
    out_deg = {}

    for e in edges:
        src = e.get("src")
        dst = e.get("dst")
        if src is not None:
            out_deg[src] = out_deg.get(src, 0) + 1
        if dst is not None:
            in_deg[dst] = in_deg.get(dst, 0) + 1

    results = []
    for n in nodes:
        nid = n.get("id")
        w = n.get("weight", 0.0)
        if nid is None:
            continue
        i_d = in_deg.get(nid, 0)
        o_d = out_deg.get(nid, 0)
        score = (i_d * 1.5) + (o_d * 0.5) + w
        results.append({"node_id": nid, "score": score})

    results.sort(key=lambda x: x["node_id"])
    print(json.dumps(results))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_relevance_calc

    # Create the image with the formula and schema
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 20,40 'RELEVANCE SCORE FORMULA:'" \
        -draw "text 20,80 'SCORE = (IN_DEGREE * 1.5) + (OUT_DEGREE * 0.5) + WEIGHT'" \
        -draw "text 20,140 'REQUIRED OUTPUT SCHEMA:'" \
        -draw "text 20,180 '['" \
        -draw "text 20,220 '  {'" \
        -draw "text 20,260 '    \"node_id\": \"string\",'" \
        -draw "text 20,300 '    \"score\": 0.0'" \
        -draw "text 20,340 '  }'" \
        -draw "text 20,380 ']'" \
        /app/relevance_formula.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
