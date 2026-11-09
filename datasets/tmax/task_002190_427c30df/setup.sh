#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/evt-start.json
{
  "event_id": "evt-start",
  "service": "api-gateway",
  "timestamp": 1700000000,
  "action": "receive_request",
  "next_event": "evt-2"
}
EOF

    cat << 'EOF' > /home/user/logs/evt-2.json
{
  "event_id": "evt-2",
  "service": "auth-service",
  "timestamp": 1700000005,
  "action": "authenticate",
  "next_event": "evt-3"
}
EOF

    cat << 'EOF' > /home/user/logs/evt-3.json
{
  "event_id": "evt-3",
  "service": "legacy-payment-service",
  "timestamp": 1700000010000,
  "action": "charge_card",
  "next_event": "evt-4"
}
EOF

    cat << 'EOF' > /home/user/logs/evt-4.json
{
  "event_id": "evt-4",
  "service": "notification-service",
  "timestamp": 1700000015,
  "action": "send_email",
  "next_event": "evt-2"
}
EOF

    cat << 'EOF' > /home/user/log_aggregator.py
import json
import os

LOG_DIR = "/home/user/logs"

def load_event(event_id):
    filepath = os.path.join(LOG_DIR, f"{event_id}.json")
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'r') as f:
        return json.load(f)

def build_timeline(start_event_id):
    timeline = []
    current_event_id = start_event_id
    last_timestamp = 0

    while current_event_id:
        event = load_event(current_event_id)
        if not event:
            break

        current_timestamp = event['timestamp']

        assert current_timestamp >= last_timestamp, f"Timeline out of order: {current_timestamp} < {last_timestamp}"

        timeline.append(event)
        last_timestamp = current_timestamp
        current_event_id = event.get('next_event')

    return timeline

if __name__ == "__main__":
    timeline = build_timeline("evt-start")
    with open("/home/user/timeline_TXN-999.json", "w") as f:
        json.dump(timeline, f, indent=2)
EOF

    chmod -R 777 /home/user
