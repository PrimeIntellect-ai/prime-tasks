#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler python3-protobuf
    pip3 install pytest

    mkdir -p /home/user/rpc_utility/schemas
    mkdir -p /home/user/rpc_utility/src
    mkdir -p /home/user/rpc_utility/data
    mkdir -p /home/user/rpc_utility/bin

    cat << 'EOF' > /home/user/rpc_utility/schemas/user.proto
syntax = "proto3";
import "request.proto";

message User {
  int32 id = 1;
  Request last_request = 2;
}
EOF

    cat << 'EOF' > /home/user/rpc_utility/schemas/request.proto
syntax = "proto3";
import "user.proto";

message Request {
  int32 req_id = 1;
  User owner = 2; // Agent needs to change this to: int32 owner_id = 2;
  int64 timestamp = 3;
}
EOF

    cat << 'EOF' > /home/user/rpc_utility/schemas/batch.proto
syntax = "proto3";
import "request.proto";

message RequestBatch {
  repeated Request requests = 1;
}
EOF

    cat << 'EOF' > /tmp/fixed_request.proto
syntax = "proto3";
message Request {
  int32 req_id = 1;
  int32 owner_id = 2;
  int64 timestamp = 3;
}
message RequestBatch {
  repeated Request requests = 1;
}
EOF

    cd /tmp
    protoc --python_out=. fixed_request.proto

    cat << 'EOF' > /tmp/gen_bin.py
import sys
sys.path.append('/tmp')
import fixed_request_pb2

batch = fixed_request_pb2.RequestBatch()

requests_data = [
    (101, 10), # req_id, owner_id
    (102, 20),
    (103, 10),
    (104, 10), # Should be rate limited (3rd for owner 10)
    (105, 20),
    (106, 30),
    (107, 10), # Should be rate limited (4th for owner 10)
    (108, 20), # Should be rate limited (3rd for owner 20)
    (109, 30)
]

for rid, oid in requests_data:
    req = batch.requests.add()
    req.req_id = rid
    req.owner_id = oid
    req.timestamp = 1600000000

with open('/home/user/rpc_utility/data/input.bin', 'wb') as f:
    f.write(batch.SerializeToString())
EOF

    python3 /tmp/gen_bin.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
