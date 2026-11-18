#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/processor

    # Create files using Python to avoid Apptainer build variable syntax errors with braces
    # and to ensure exact decomposed Unicode sequences are written.
    python3 -c '
import os

# Write report.tmpl
with open("/home/user/report.tmpl", "w", encoding="utf-8") as f:
    f.write("# Review Processing Report\n")
    f.write("Total Reviews Parsed: {" + "{.Total}" + "}\n")
    f.write("Clean Reviews: {" + "{.CleanCount}" + "}\n")
    f.write("Anomalous Reviews: {" + "{.AnomalyCount}" + "}\n")
    f.write("Duplicates Removed: {" + "{.DuplicateCount}" + "}\n")

# Write reviews.csv
with open("/home/user/reviews.csv", "w", encoding="utf-8") as f:
    f.write("ReviewID,UserID,Language,Text\n")
    f.write("1,U1,en,Great app!\n")
    f.write("2,U1,en,Great app!\n")
    # Row 3 uses decomposed "a" + U+0301
    f.write("3,U2,es,Fant" + "a\u0301" + "stico\n")
    f.write("4,U3,ja,こんにちは\n")
    f.write("5,U4,en,This is terribleeeeee!!!!!!!!!!\n")
    f.write("6,U4,en,This is terribleeeeee!!!!!!!!!!\n")
    f.write("7,U5,ar,مرحبا\n")
    f.write("8,U3,ja,こんにちは\n")
    f.write("9,U6,en,Wowwwwwwwwww\n")
'

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
