#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools

mkdir -p /app/tiny_vm_grpc/src
mkdir -p /app/tiny_vm_grpc/proto
mkdir -p /app/tiny_vm_grpc/tests

cat << 'EOF' > /app/tiny_vm_grpc/proto/vm_service.proto
syntax = "proto3";
package vm;
service VMService {
  rpc Execute (ProgramRequest) returns (ProgramResponse) {}
}
message ProgramRequest {
  string code = 1;
}
message ProgramResponse {
  int32 result = 1;
}
EOF

cat << 'EOF' > /app/tiny_vm_grpc/src/utils.py
def compare_versions(v1, v2):
    parts1 = [int(x) for x in v1.split('.')]
    parts2 = [int(x) for x in v2.split('.')]
    return cmp(parts1, parts2)
EOF

cat << 'EOF' > /app/tiny_vm_grpc/src/vm.py
class TinyVM:
    def __init__(self):
        self.registers = {'R1': 0, 'R2': 0}

    def execute(self, program_string):
        pc = 0
        while True:
            # INNEFICIENT PARSING INSIDE LOOP
            lines = program_string.strip().split('\n')
            if pc >= len(lines):
                break

            line = lines[pc].strip()
            if not line:
                pc += 1
                continue

            parts = line.split()
            cmd = parts[0]

            if cmd == "SET":
                self.registers[parts[1]] = int(parts[2])
            elif cmd == "ADD":
                self.registers[parts[1]] += int(parts[2])
            elif cmd == "SUB":
                self.registers[parts[1]] -= int(parts[2])
            elif cmd == "JNZ":
                if not self.registers.has_key(parts[1]):
                    self.registers[parts[1]] = 0
                if self.registers[parts[1]] != 0:
                    pc = int(parts[2])
                    continue
            elif cmd == "HALT":
                break
            pc += 1

        return self.registers['R1']
EOF

cat << 'EOF' > /app/tiny_vm_grpc/src/server.py
from concurrent import futures
import grpc
import vm_service_pb2
import vm_service_pb2_grpc
from vm import TinyVM

class VMServiceServicer(vm_service_pb2_grpc.VMServiceServicer):
    def Execute(self, request, context):
        vm = TinyVM()
        res = vm.execute(request.code)
        return vm_service_pb2.ProgramResponse(result=res)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    vm_service_pb2_grpc.add_VMServiceServicer_to_server(VMServiceServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

cat << 'EOF' > /app/tiny_vm_grpc/benchmark.py
import time
import grpc
import sys
import threading
sys.path.append('./src')
import vm_service_pb2
import vm_service_pb2_grpc
import server

def run_benchmark():
    code = "SET R1 0\nSET R2 10000\nADD R1 1\nSUB R2 1\nJNZ R2 2\nHALT\n"

    channel = grpc.insecure_channel('localhost:50051')
    stub = vm_service_pb2_grpc.VMServiceStub(channel)

    start = time.time()
    response = stub.Execute(vm_service_pb2.ProgramRequest(code=code))
    end = time.time()

    duration = end - start
    with open('benchmark_result.txt', 'w') as f:
        f.write(str(duration))
    print(f"Result: {response.result}, Time: {duration}")

if __name__ == '__main__':
    t = threading.Thread(target=server.serve, daemon=True)
    t.start()
    time.sleep(1) # wait for server
    run_benchmark()
EOF

cat << 'EOF' > /app/tiny_vm_grpc/tests/test_vm.py
import sys
sys.path.append('./src')
from vm import TinyVM
from utils import compare_versions

def test_compare_versions():
    assert compare_versions("1.0", "1.1") < 0
    assert compare_versions("2.0", "2.0") == 0
    assert compare_versions("2.1", "2.0") > 0

def test_vm_execution():
    vm = TinyVM()
    res = vm.execute("SET R1 10\nADD R1 5\nHALT\n")
    assert res == 15
EOF

cat << 'EOF' > /app/tiny_vm_grpc/requirements.txt
grpcio
grpcio-tools
pytest
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
