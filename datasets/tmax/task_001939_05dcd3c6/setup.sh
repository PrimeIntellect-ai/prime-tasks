#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/math_dag

    cat << 'EOF' > /home/user/math_dag/math_graph.proto
syntax = "proto3";

message Node {
    string id = 1;
    string operation = 2; // e.g., "ADD", "MUL"
    repeated string dependencies = 3;
}

message Graph {
    repeated Node nodes = 1;
}

message InstructionSet {
    repeated string instructions = 1;
}

service ExecutionEngine {
    rpc Compile(Graph) returns (InstructionSet);
}
EOF

    cat << 'EOF' > /home/user/math_dag/Makefile
build:
	# PR broke this line
	python3 -m grpc_tools.protoc -I. --python_out=. math_graph.proto
	# Missing the grpc_python_out

clean:
	rm -f *_pb2*.py output.txt diff_result.txt
EOF

    cat << 'EOF' > /home/user/math_dag/server.py
import grpc
from concurrent import futures
import math_graph_pb2
import math_graph_pb2_grpc

class ExecutionEngineServicer(math_graph_pb2_grpc.ExecutionEngineServicer):
    def Compile(self, request, context):
        # Build adjacency list and in-degrees
        adj = {node.id: [] for node in request.nodes}
        in_degree = {node.id: 0 for node in request.nodes}
        ops = {node.id: node.operation for node in request.nodes}

        for node in request.nodes:
            for dep in node.dependencies:
                adj[dep].append(node.id)
                in_degree[node.id] += 1

        # Topological Sort (Kahn's)
        queue = [nid for nid in in_degree if in_degree[nid] == 0]
        queue.sort() # For deterministic output

        sorted_nodes = []
        while queue:
            curr = queue.pop(0)
            sorted_nodes.append(curr)

            for neighbor in adj[curr]:
                # BUG INTRODUCED BY PR: should decrement in_degree of neighbor
                in_degree[curr] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)
            queue.sort()

        if len(sorted_nodes) != len(request.nodes):
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details('Graph contains a cycle')
            return math_graph_pb2.InstructionSet()

        instructions = [f"EXEC {ops[nid]} {nid}" for nid in sorted_nodes]
        return math_graph_pb2.InstructionSet(instructions=instructions)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    math_graph_pb2_grpc.add_ExecutionEngineServicer_to_server(ExecutionEngineServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /home/user/math_dag/client.py
import grpc
import math_graph_pb2
import math_graph_pb2_grpc

def run():
    channel = grpc.insecure_channel('localhost:50051')
    stub = math_graph_pb2_grpc.ExecutionEngineStub(channel)

    # Graph:
    # A -> B, A -> C
    # B -> D
    # C -> D
    # D -> E
    graph = math_graph_pb2.Graph(
        nodes=[
            math_graph_pb2.Node(id="E", operation="MUL", dependencies=["D"]),
            math_graph_pb2.Node(id="D", operation="ADD", dependencies=["B", "C"]),
            math_graph_pb2.Node(id="C", operation="SUB", dependencies=["A"]),
            math_graph_pb2.Node(id="B", operation="MUL", dependencies=["A"]),
            math_graph_pb2.Node(id="A", operation="LOAD", dependencies=[]),
        ]
    )

    try:
        response = stub.Compile(graph)
        with open("output.txt", "w") as f:
            for instr in response.instructions:
                f.write(instr + "\n")
    except Exception as e:
        print("RPC failed:", e)

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > /home/user/math_dag/expected.txt
EXEC LOAD A
EXEC MUL B
EXEC SUB C
EXEC ADD D
EXEC MUL E
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
