#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    mkdir -p /app /oracle

    python3 -c '
from PIL import Image, ImageDraw
img = Image.new("RGB", (200, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "en-US\nfr-FR\nzh-CN\npt-BR", fill=(0,0,0))
img.save("/app/locales.png")
'

    cat << 'EOF' > /oracle/process.py
import sys
import json
import math

VALID_LOCALES = {"en-US", "fr-FR", "zh-CN", "pt-BR"}

def main():
    data = {}
    for line in sys.stdin:
        try:
            obj = json.loads(line)
            if 'ts' not in obj or 'loc' not in obj or 'lat' not in obj:
                continue
            ts = int(obj['ts'])
            loc = str(obj['loc'])
            lat = float(obj['lat'])
            if loc not in VALID_LOCALES:
                continue
            if loc not in data:
                data[loc] = {}
            if ts not in data[loc]:
                data[loc][ts] = []
            data[loc][ts].append(lat)
        except Exception:
            pass

    out = {}
    for loc, ts_dict in data.items():
        if len(ts_dict) < 2:
            continue

        sorted_ts = sorted(ts_dict.keys())
        deduped = []
        for ts in sorted_ts:
            avg_lat = sum(ts_dict[ts]) / len(ts_dict[ts])
            deduped.append((ts, avg_lat))

        all_points = []
        imputed_count = 0
        for i in range(len(deduped)):
            all_points.append(deduped[i][1])
            if i < len(deduped) - 1:
                ts_a, lat_a = deduped[i]
                ts_b, lat_b = deduped[i+1]

                k = 1
                while True:
                    ts_impute = ts_a + k * 60
                    if ts_impute >= ts_b:
                        break
                    lat_impute = lat_a + (lat_b - lat_a) * (ts_impute - ts_a) / (ts_b - ts_a)
                    all_points.append(lat_impute)
                    imputed_count += 1
                    k += 1

        overall_avg = sum(all_points) / len(all_points)
        floored_avg = math.floor(overall_avg * 100) / 100.0

        out[loc] = {
            "start_ts": deduped[0][0],
            "end_ts": deduped[-1][0],
            "original_points": len(deduped),
            "imputed_points": imputed_count,
            "avg_lat": floored_avg
        }

    print(json.dumps(out))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
