#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c '
import gzip
import os

log_data = """2023-10-24T10:00:00 INFO System started
2023-10-24T10:01:00 INFO Loading job
[GCODE_START]
G28
G1 X10 Y10 F1000
M104 S200
[GCODE_END]
2023-10-24T10:02:00 INFO Job finished
2023-10-24T10:05:00 CRITICAL Axis X limit switch hit
2023-10-24T10:06:00 INFO Recovering
[GCODE_START]
G90
G1 Z10 F500
[GCODE_END]
2023-10-24T10:10:00 CRITICAL Temperature runaway on extruder 1
2023-10-24T10:11:00 INFO System halted
"""

with gzip.open("/home/user/robot_dump.log.gz", "wt") as f:
    f.write(log_data)
'

    chmod -R 777 /home/user
