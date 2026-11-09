#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/event_processor.py
import threading
import json
import time
from concurrent.futures import ThreadPoolExecutor

class Aggregator:
    def __init__(self):
        self.stats = {}

    def process_event(self, event_json):
        try:
            event = json.loads(event_json)
            user = event.get('user')
            amount = event.get('amount', 0)

            if user is None:
                return

            # Simulate processing time to widen the race condition window
            current = self.stats.get(user, 0)
            time.sleep(0.0001) 
            self.stats[user] = current + amount
        except json.JSONDecodeError:
            pass

    def get_stats(self):
        return self.stats

def run_batch(events, max_workers=20):
    agg = Aggregator()
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        executor.map(agg.process_event, events)
    return agg.get_stats()
EOF

    cp /home/user/app/event_processor.py /home/user/app/event_processor_buggy.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
