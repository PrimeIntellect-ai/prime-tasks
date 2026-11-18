#!/usr/bin/env python3
import sys
import csv
import json
import re
from dateutil import parser

def process():
    reader = csv.DictReader(sys.stdin)
    for row in reader:
        raw_time = row.pop('raw_time')
        dt = parser.parse(raw_time)
        dt = dt.replace(second=0, microsecond=0)
        ts_str = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        sensors = sorted(row.keys())
        for sensor in sensors:
            val_str = row[sensor]
            m = re.match(r'\[VAL:\s*([-\d\.]+)\]\s*\[STATUS:\s*([A-Z]+)\]', val_str)
            if m:
                val = float(m.group(1))
                status = m.group(2)
                if status == "OK" and val >= 0.0:
                    out = {"ts": ts_str, "sensor": sensor, "val": val}
                    print(json.dumps(out))

if __name__ == '__main__':
    process()
