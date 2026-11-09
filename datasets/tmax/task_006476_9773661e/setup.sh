#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools

mkdir -p /home/user/graph_service
cd /home/user/graph_service

cat << 'EOF' > graph.proto
syntax = "proto3";

// Broken proto file
message Edge {
  int32 source = 1;
  int32 target = 2;
}

message GraphRequest {
  repeated edges = 1;
}

message GraphResponse {
  repeated int32 sorted_nodes = 1;
}

service GraphService {
  rpc TopologicalSort(GraphRequest) returns (GraphResponse);
}
EOF

cat << 'EOF' > server.py
import grpc
from concurrent import futures
import graph_pb2
import graph_pb2_grpc
from collections import defaultdict, deque

class GraphServiceServicer(graph_pb2_grpc.GraphServiceServicer):
    def TopologicalSort(self, request, context):
        adj = defaultdict(list)
        in_degree = defaultdict(int)
        nodes = set()

        for edge in request.edges:
            adj[edge.source].append(edge.target)
            in_degree[edge.target] += 1
            nodes.add(edge.source)
            nodes.add(edge.target)

        # Buggy queue: doesn't sort by ID, just uses standard deque
        queue = deque([n for n in nodes if in_degree[n] == 0])
        result = []

        while queue:
            # Bug: Just pops left, doesn't respect the tie-breaking rule
            node = queue.popleft()
            result.append(node)
            for neighbor in adj[node]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        return graph_pb2.GraphResponse(sorted_nodes=result)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    graph_pb2_grpc.add_GraphServiceServicer_to_server(GraphServiceServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
