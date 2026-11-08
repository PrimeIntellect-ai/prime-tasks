#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
mkdir -p /home/user/service

# Create the crash log
cat << 'EOF' > /home/user/logs/crash.log
Traceback (most recent call last):
  File "/home/user/service/run_production.py", line 42, in <module>
    asyncio.run(main())
  File "/usr/lib/python3.10/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "/usr/lib/python3.10/asyncio/base_events.py", line 646, in run_until_complete
    return future.result()
  File "/home/user/service/run_production.py", line 25, in main
    data = await aggregator.fetch_data_with_retry("http://internal-metrics.local", retries=3)
  File "/home/user/service/aggregator.py", line 18, in fetch_data_with_retry
    return await self.fetch_data_with_retry(endpoint, retries=retries)
  File "/home/user/service/aggregator.py", line 18, in fetch_data_with_retry
    return await self.fetch_data_with_retry(endpoint, retries=retries)
  [Previous line repeated 995 more times]
RecursionError: maximum recursion depth exceeded while calling a Python object
EOF

# Create the buggy aggregator.py
cat << 'EOF' > /home/user/service/aggregator.py
import asyncio
import math

class MetricsAggregator:
    def __init__(self):
        self.max_retries = 3

    async def fetch_data_with_retry(self, endpoint, retries=None):
        if retries is None:
            retries = self.max_retries
        if retries <= 0:
            return []

        try:
            # Simulate a network timeout that triggers the retry block
            raise asyncio.TimeoutError()
        except asyncio.TimeoutError:
            # BUG 1: Retries counter is not decremented, causing infinite recursion
            return await self.fetch_data_with_retry(endpoint, retries=retries)

    def compute_standard_deviation(self, values):
        n = len(values)
        if n < 2: 
            return 0.0

        # BUG 2: Catastrophic cancellation / numerical instability
        # Using the naive sum of squares formula causes issues with floats
        sum_sq = sum(x * x for x in values)
        sq_sum = sum(values) ** 2
        variance = (sum_sq - sq_sum / n) / (n - 1)

        # This will raise a ValueError if variance is slightly negative due to floating point limits
        return math.sqrt(variance)
EOF

# Create the runner script
cat << 'EOF' > /home/user/service/run_production.py
import asyncio
import json
from aggregator import MetricsAggregator

async def main():
    aggregator = MetricsAggregator()

    # Test fetch_data_with_retry (should return [] after retries are exhausted, not crash)
    result = await aggregator.fetch_data_with_retry("http://metrics-api.local", retries=3)
    if result != []:
        print("Error: Expected empty list after exhausting retries.")
        return

    # High precision float data prone to catastrophic cancellation in naive formulas
    # These represent large closely spaced values (e.g., timestamps or high-value financial ticks)
    dataset = [100000000.0, 100000000.1, 100000000.2]

    try:
        stdev = aggregator.compute_standard_deviation(dataset)
    except Exception as e:
        print(f"Error computing standard deviation: {e}")
        return

    output = {
        "status": "success",
        "retries_exhausted_gracefully": True,
        "standard_deviation": round(stdev, 5)
    }

    with open("/home/user/metrics_output.json", "w") as f:
        json.dump(output, f, indent=2)

    print("Production run complete. Output written to /home/user/metrics_output.json")

if __name__ == "__main__":
    asyncio.run(main())
EOF

chmod +x /home/user/service/run_production.py
chmod -R 777 /home/user
