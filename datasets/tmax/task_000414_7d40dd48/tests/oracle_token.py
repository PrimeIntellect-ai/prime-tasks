#!/usr/bin/env python3
import sys

def generate_token(service_name, timestamp):
    rev_name = service_name[::-1]
    ts_mult = int(timestamp) * 3
    token = f"{rev_name}-{ts_mult}"
    if service_name.startswith("db"):
        token += "-admin"
    return token

if __name__ == "__main__":
    print(generate_token(sys.argv[1], sys.argv[2]))
