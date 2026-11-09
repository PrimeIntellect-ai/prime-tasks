import sys
import json
import csv
from text_cleaner_lib import redact_emails, tokenize_and_normalize

def load_lookup():
    d = {}
    with open('/app/lookup.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            d[int(row['user_id'])] = {'region': row['region'], 'risk_score': int(row['risk_score'])}
    return d

def main():
    lookup = load_lookup()
    for line in sys.stdin:
        if not line.strip(): continue
        data = json.loads(line)
        uid = data['user_id']
        info = lookup.get(uid, {'region': 'UNKNOWN', 'risk_score': 0})
        if info['risk_score'] > 90:
            continue

        msg = redact_emails(data['message'])
        tokens = tokenize_and_normalize(msg)

        out = {
            "user_id": uid,
            "region": info['region'],
            "clean_tokens": tokens,
            "timestamp": data['timestamp']
        }
        print(json.dumps(out))

if __name__ == '__main__':
    main()
