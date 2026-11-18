#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl build-essential cargo rustc
    pip3 install pytest grpcio grpcio-tools hypothesis maturin

    mkdir -p /home/user/project/rust_ext/src
    mkdir -p /home/user/project/proto

    cat << 'EOF' > /home/user/project/rust_ext/Cargo.toml
[package]
name = "string_processor"
version = "0.1.0"
edition = "2021"

[lib]
name = "string_processor"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/project/rust_ext/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"
EOF

    cat << 'EOF' > /home/user/project/rust_ext/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn process_string(s: &str, multiplier: i32) -> &str {
    let mut res = String::new();
    for _ in 0..multiplier {
        res.push_str(s);
    }
    res // This causes a lifetime error. The agent needs to change the return type to String.
}

#[pymodule]
fn string_processor(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(process_string, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/project/proto/service.proto
syntax = "proto3";

package processor;

service ProcessorService {
  rpc Process (ProcessRequest) returns (ProcessResponse);
}

message ProcessRequest {
  string input_text = 1;
}

message ProcessResponse {
  string output_text = 1;
}
EOF

    cat << 'EOF' > /home/user/project/server.py
import grpc
from concurrent import futures
import service_pb2
import service_pb2_grpc
import string_processor

class ProcessorServicer(service_pb2_grpc.ProcessorServiceServicer):
    def Process(self, request, context):
        # Agent needs to handle multiplier here
        multiplier = 1
        result = string_processor.process_string(request.input_text, multiplier)
        return service_pb2.ProcessResponse(output_text=result)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_ProcessorServiceServicer_to_server(ProcessorServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
