#!/usr/bin/env python3
import sys

rates = {
    "US_EAST": 0.12,
    "US_WEST": 0.17,
    "EU_CENTRAL": 0.22
}

total = 0.0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) == 2:
        region = parts[0]
        hours = int(parts[1])
        if region in rates:
            total += rates[region] * hours

print("From: finops@local")
print("To: billing-alerts@local")
print("Subject: Daily Cloud Cost Alert")
print()
print(f"Total Cost: ${total:.2f}")
