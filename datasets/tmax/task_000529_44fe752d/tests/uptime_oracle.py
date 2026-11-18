#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    try:
        data = json.loads(sys.argv[1])
        server = data["server"]
        pings = int(data["pings"])
        missed = int(data["missed"])
        uptime = ((pings - missed) / float(pings)) * 100.0
        print(f"Server {server}: {uptime:.2f}%")
    except Exception as e:
        sys.exit(1)

if __name__ == "__main__":
    main()
