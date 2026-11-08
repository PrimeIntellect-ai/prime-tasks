import sys
import re
import json

def parse_log(log_str):
    ip_pattern = r'(?:Connection closed by |Disconnecting from )(\d{1,3}(?:\.\d{1,3}){3})'
    ips = re.findall(ip_pattern, log_str)

    # Filter valid IPs mathematically
    valid_ips = []
    for ip in ips:
        parts = ip.split('.')
        if all(0 <= int(p) <= 255 for p in parts):
            valid_ips.append(ip)

    unique_ips = sorted(list(set(valid_ips)))
    key_failures = log_str.count('publickey')

    print(json.dumps({"failed_ips": unique_ips, "key_failures": key_failures}))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        parse_log(sys.argv[1])
    else:
        print(json.dumps({"failed_ips": [], "key_failures": 0}))
