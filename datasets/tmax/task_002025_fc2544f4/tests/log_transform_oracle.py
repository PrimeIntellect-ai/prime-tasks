import sys
import json
from collections import defaultdict

def process_logs(file_path):
    users = defaultdict(list)
    with open(file_path, 'r') as f:
        for line in f:
            if not line.strip(): continue
            record = json.loads(line)
            users[record['user_id']].append(record)

    all_records = []
    for uid, records in users.items():
        records.sort(key=lambda x: x['timestamp'])
        for i, r in enumerate(records):
            latency = float(r['latency'])
            if i == 0:
                sma = latency
                diff = 0.0
            elif i == 1:
                sma = (float(records[0]['latency']) + latency) / 2
                diff = abs(latency - float(records[0]['latency']))
            else:
                sma = (float(records[i-2]['latency']) + float(records[i-1]['latency']) + latency) / 3
                diff = abs(latency - float(records[i-1]['latency']))

            all_records.append({
                'timestamp': r['timestamp'],
                'user_id': uid,
                'endpoint': r['endpoint'],
                'latency': latency,
                'rolling_avg_latency': sma,
                'latency_diff': diff
            })

    all_records.sort(key=lambda x: (x['timestamp'], x['user_id']))

    print("timestamp,user_id,endpoint,latency,rolling_avg_latency,latency_diff")
    for r in all_records:
        print(f"{r['timestamp']},{r['user_id']},{r['endpoint']},{r['latency']:.4f},{r['rolling_avg_latency']:.4f},{r['latency_diff']:.4f}")

if __name__ == '__main__':
    process_logs(sys.argv[1])
