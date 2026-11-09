#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/combined.jsonl
{"timestamp": 1600000000, "trace_id": "req-1", "event_type": "START"}
{"timestamp": 1600000005, "trace_id": "req-1", "event_type": "END"}
{"timestamp": 1600000010, "trace_id": "req-2", "event_type": "START"}
{"timestamp": 1600000012, "trace_id": "req-3", "event_type": "START"}
{"timestamp": 1600000013, "trace_id": "req-2", "event_type": "END"}
{"timestamp": 1600000014, "trace_id": "req-4", "event_type": "END"}
{"timestamp": 1600000015, "trace_id": "req-4", "event_type": "START"}
{"timestamp": 1600000016, "trace_id": "req-3", "event_type": "END"}
{"timestamp": 1600000017, "trace_id": "req-5", "event_type": "START"}
{"timestamp": 1600000020, "trace_id": "req-5", "event_type": "END"}
EOF

    cd /home/user
    cargo new trace_aggregator
    cd trace_aggregator
    cargo add serde -F derive
    cargo add serde_json

    cat << 'EOF' > /home/user/trace_aggregator/src/main.rs
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
struct LogEvent {
    timestamp: u64,
    trace_id: String,
    event_type: String,
}

#[derive(Debug, Serialize)]
struct CompletedTrace {
    trace_id: String,
    total_duration: u64,
}

fn main() {
    let mut active_traces: HashMap<String, u64> = HashMap::new();
    let mut completed = Vec::new();

    let file = File::open("/home/user/logs/combined.jsonl").unwrap();
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let event: LogEvent = serde_json::from_str(&line).unwrap();

        if event.event_type == "START" {
            active_traces.insert(event.trace_id, event.timestamp);
        } else if event.event_type == "END" {
            let start_time = active_traces.get(&event.trace_id).unwrap(); // CRASH HERE
            let duration = event.timestamp - start_time;
            completed.push(CompletedTrace {
                trace_id: event.trace_id.clone(),
                total_duration: duration,
            });
        }
    }

    let out = File::create("/home/user/completed_traces.json").unwrap();
    serde_json::to_writer_pretty(&out, &completed).unwrap();
}
EOF

    chmod -R 777 /home/user
