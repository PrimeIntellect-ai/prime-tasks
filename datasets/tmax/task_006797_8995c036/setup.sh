#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/rust_log_parser
    cd /home/user/rust_log_parser

    cat << 'EOF' > models.py
from dataclasses import dataclass
from typing import List
from parser import parse_span

@dataclass
class RustError:
    code: str
    message: str
    file_name: str
    line: int

def create_error(msg: dict) -> RustError:
    code = msg.get("code", {}).get("code", "UNKNOWN")
    message = msg.get("message", "")
    spans = msg.get("spans", [])
    if spans:
        file_name, line = parse_span(spans[0])
    else:
        file_name, line = "unknown", 0
    return RustError(code=code, message=message, file_name=file_name, line=line)
EOF

    cat << 'EOF' > parser.py
import json
from models import RustError, create_error

def parse_span(span: dict) -> tuple:
    return span.get("file_name", "unknown"), span.get("line_start", 0)

class LogParser:
    def __init__(self):
        self.state = "INIT"
        self.errors = []
        self.current_error = None

    def process_line(self, line: str):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            return

        if data.get("reason") == "compiler-message":
            msg = data.get("message", {})
            if msg.get("level") == "error":
                # Check if it's an aborting message
                if "aborting due to" in msg.get("message", ""):
                    if self.state == "IN_ERROR" and self.current_error:
                        self.errors.append(self.current_error)
                        self.current_error = None
                    self.state = "DONE"
                else:
                    if self.state == "IN_ERROR" and self.current_error:
                        self.errors.append(self.current_error)
                    self.current_error = create_error(msg)
                    self.state = "IN_ERROR"
EOF

    cat << 'EOF' > main.py
import sys
import json
from parser import LogParser

def main():
    if len(sys.argv) < 3:
        print("Usage: python main.py <input> <output>")
        sys.exit(1)

    parser = LogParser()
    with open(sys.argv[1], 'r') as f:
        for line in f:
            if not line.strip(): continue
            parser.process_line(line)

    # MISSING: parser.finalize()

    with open(sys.argv[2], 'w') as f:
        json.dump([e.__dict__ for e in parser.errors], f, indent=2)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > cargo_errors.jsonl
{"reason":"compiler-artifact","package_id":"my_project 0.1.0"}
{"reason":"compiler-message","message":{"message":"cannot borrow `x` as mutable, as it is not declared as mutable","code":{"code":"E0596"},"level":"error","spans":[{"file_name":"src/main.rs","line_start":5}]}}
{"reason":"compiler-message","message":{"message":"value borrowed here after move","code":{"code":"E0382"},"level":"error","spans":[{"file_name":"src/main.rs","line_start":10}]}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
