import sys
import json

def process(infile, outfile):
    with open(infile, 'r') as f:
        data = json.load(f)

    data.sort(key=lambda x: x.get('timestamp', 0))

    filtered = []
    for event in data:
        svc = event.get('service', '')
        if svc == 'SSH':
            if event.get('auth_method', '') == 'password':
                continue
        elif svc == 'WAF':
            payload = event.get('payload', '')
            if 'UNION SELECT' in payload or '<script>' in payload:
                continue
        filtered.append(event)

    with open(outfile, 'w') as f:
        json.dump(filtered, f, indent=2)

if __name__ == "__main__":
    process(sys.argv[1], sys.argv[2])
