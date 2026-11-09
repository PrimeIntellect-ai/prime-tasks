import sys
import csv
import json
from datetime import datetime, timedelta

def run():
    content = sys.stdin.read()
    # Use csv module to correctly handle quoted newlines
    reader = csv.reader(content.splitlines(keepends=True))
    header = next(reader, None)

    buckets = {}

    for row in reader:
        if not row or len(row) < 4:
            continue
        timestamp_str, sensor_id, temp_str, status_log = row

        # Rule: Drop rows with embedded newlines in status_log
        if '\n' in status_log:
            continue

        try:
            dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            temp = float(temp_str)
        except ValueError:
            continue

        # 15-minute tumbling window
        minute_bucket = (dt.minute // 15) * 15
        bucket_dt = dt.replace(minute=minute_bucket, second=0, microsecond=0)
        bucket_str = bucket_dt.isoformat()
        if bucket_str.endswith('+00:00'):
            bucket_str = bucket_str.replace('+00:00', 'Z')

        if bucket_str not in buckets:
            buckets[bucket_str] = []
        buckets[bucket_str].append(temp)

    results = []
    for bucket in sorted(buckets.keys()):
        temps = buckets[bucket]
        mean_temp = sum(temps) / len(temps)
        results.append({
            "window_start": bucket,
            "mean_temp": round(mean_temp, 2)
        })

    print(json.dumps(results, separators=(',', ':')))

if __name__ == '__main__':
    run()
