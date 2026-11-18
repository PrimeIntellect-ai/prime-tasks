#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools protobuf

    mkdir -p /home/user/grpc_state_service
    cd /home/user/grpc_state_service

    cat << 'EOF' > service.proto
syntax = "proto3";

package state_parser;

service LogParser {
  rpc ParseEvent (ParseRequest) returns (ParseResponse) {}
}

message ParseRequest {
  string client_version = 1;
  string event_name = 2;
}

message ParseResponse {
  bool accepted = 1;
  string current_state = 2;
  string error_message = 3;
}
EOF

    cat << 'EOF' > server.py
import grpc
from concurrent import futures
import service_pb2
import service_pb2_grpc

class LogParserServicer(service_pb2_grpc.LogParserServicer):
    def __init__(self):
        self.state = "INIT"
        self.transitions = {
            "INIT": {"START": "RUNNING"},
            "RUNNING": {"PAUSE": "PAUSED", "HLT": "STOPPED"}, # Bug: HLT instead of HALT
            "PAUSED": {"RESUME": "RUNNING"}
        }

    def check_version(self, client_version, min_version):
        # Bug: string comparison fails for "1.10.0" vs "1.9.0"
        return client_version >= min_version

    def ParseEvent(self, request, context):
        if not self.check_version(request.client_version, "1.9.0"):
            return service_pb2.ParseResponse(accepted=False, current_state=self.state, error_message="Version too old")

        # This will fail if sequence_number isn't in proto
        seq = request.sequence_number

        event = request.event_name
        if event in self.transitions.get(self.state, {}):
            self.state = self.transitions[self.state][event]
            return service_pb2.ParseResponse(accepted=True, current_state=self.state, error_message="")
        else:
            return service_pb2.ParseResponse(accepted=False, current_state=self.state, error_message="Invalid transition")

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_LogParserServicer_to_server(LogParserServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > client_test.py
import grpc
import service_pb2
import service_pb2_grpc
import threading
import time
import json
import os
import subprocess

def run_server():
    proc = subprocess.Popen(["python3", "server.py"])
    time.sleep(2)
    return proc

def run_client():
    channel = grpc.insecure_channel('localhost:50051')
    stub = service_pb2_grpc.LogParserStub(channel)

    events = [
        ("1.10.0", "START", 1),
        ("1.10.0", "PAUSE", 2),
        ("1.10.0", "RESUME", 3),
        ("1.10.0", "HALT", 4)
    ]

    final_state = ""
    success = True

    start_time = time.time()
    for version, event, seq in events:
        try:
            req = service_pb2.ParseRequest(client_version=version, event_name=event, sequence_number=seq)
            resp = stub.ParseEvent(req)
            if not resp.accepted:
                success = False
            final_state = resp.current_state
        except Exception as e:
            success = False
            break

    end_time = time.time()

    with open("/home/user/test_result.json", "w") as f:
        json.dump({
            "status": "success" if success and final_state == "STOPPED" else "failed",
            "final_state": final_state,
            "benchmark_ms": round((end_time - start_time) * 1000)
        }, f)

if __name__ == '__main__':
    proc = run_server()
    try:
        run_client()
    finally:
        proc.terminate()
EOF

    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. service.proto

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
