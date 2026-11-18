#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        g++ \
        zlib1g-dev \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the policy image using ImageMagick directly with text (avoiding @ file reading)
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -annotate +20+40 "ARTIFACT POLICY UPDATE
To prevent supply chain attacks, all manifests must adhere to the following rules:
1. The JSON must contain both 'author' and 'build_id' fields.
2. The 'total_uncompressed_bytes' must be strictly less than 50000000.
3. The number of elements in the 'chunks' array must be exactly 3.
4. The 'compression_format' must be exactly \"gzip\"." \
    /app/artifact_policy.png

    # Generate corpus files using Python
    python3 -c '
import json
import gzip
import os

base = {
  "artifact_name": "backend_service",
  "author": "dev_team_alpha",
  "build_id": "bld_9921",
  "compression_format": "gzip",
  "total_uncompressed_bytes": 45000000,
  "chunks": [
    {"part": 1, "size": 15000000},
    {"part": 2, "size": 15000000},
    {"part": 3, "size": 15000000}
  ]
}

def write_gz(path, data):
    with gzip.open(path, "wt") as f:
        json.dump(data, f)

write_gz("/app/corpora/clean/clean1.json.gz", base)

evil_size = base.copy()
evil_size["total_uncompressed_bytes"] = 50000000
write_gz("/app/corpora/evil/evil_size.json.gz", evil_size)

evil_chunks = base.copy()
evil_chunks["chunks"] = [{"part": 1, "size": 15000000}, {"part": 2, "size": 15000000}]
write_gz("/app/corpora/evil/evil_chunks.json.gz", evil_chunks)

evil_missing_author = base.copy()
del evil_missing_author["author"]
write_gz("/app/corpora/evil/evil_missing_author.json.gz", evil_missing_author)

evil_format = base.copy()
evil_format["compression_format"] = "bzip2"
write_gz("/app/corpora/evil/evil_format.json.gz", evil_format)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
