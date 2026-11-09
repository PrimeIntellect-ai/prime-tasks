#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest protobuf grpcio-tools

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph.proto
syntax = "proto3";

message Node {
  string id = 1;
  repeated string depends_on = 2;
}

message Graph {
  repeated Node nodes = 1;
}
EOF

    cd /home/user
    python3 -m grpc_tools.protoc -I. --python_out=. graph.proto

    cat << 'EOF' > /home/user/setup_data.py
import graph_pb2

graph = graph_pb2.Graph()

# E has no dependencies
n = graph.nodes.add()
n.id = "E"

# D depends on E
n = graph.nodes.add()
n.id = "D"
n.depends_on.extend(["E"])

# C depends on D, E
n = graph.nodes.add()
n.id = "C"
n.depends_on.extend(["D", "E"])

# B depends on D
n = graph.nodes.add()
n.id = "B"
n.depends_on.extend(["D"])

# A depends on B, C
n = graph.nodes.add()
n.id = "A"
n.depends_on.extend(["B", "C"])

# F depends on A
n = graph.nodes.add()
n.id = "F"
n.depends_on.extend(["A"])

# G depends on B
n = graph.nodes.add()
n.id = "G"
n.depends_on.extend(["B"])

with open("/home/user/graph_data.bin", "wb") as f:
    f.write(graph.SerializeToString())
EOF

    python3 /home/user/setup_data.py

    rm /home/user/graph_pb2.py /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
