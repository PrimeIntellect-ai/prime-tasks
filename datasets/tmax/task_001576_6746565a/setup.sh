#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataproc

    cat << 'EOF' > /home/user/dataproc/models.py
import json
from validator import validate_event

class Event:
    def __init__(self, name: str, payload: dict):
        self.name = name
        self.payload = payload

    def to_json(self) -> str:
        return json.dumps({"name": self.name, "payload": self.payload})

    @classmethod
    def from_json(cls, data: str) -> 'Event':
        d = json.loads(data)
        return cls(name=d["name"], payload=d["payload"])

    def process(self):
        if validate_event(self):
            print(f"Processing {self.name}")
EOF

    cat << 'EOF' > /home/user/dataproc/validator.py
from models import Event
import time

# Dictionary to store request timestamps per client_id
_client_requests = {}

def validate_event(event: Event) -> bool:
    if not event.name:
        return False
    return rate_limit_check(event.name)

def rate_limit_check(client_id: str) -> bool:
    """
    Returns True if the client is under the limit of 3 requests per second.
    Otherwise False.
    """
    pass # TODO: implement
EOF

    cat << 'EOF' > /home/user/dataproc/test_models.py
import pytest
from hypothesis import given, strategies as st
from models import Event

# TODO: implement test_event_serialization_symmetry using hypothesis
EOF

    chown -R user:user /home/user/dataproc
    chmod -R 777 /home/user
