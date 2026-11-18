#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget procps
    pip3 install pytest grpcio grpcio-tools grpcio-reflection

    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
    tar -xvf grpcurl_1.8.7_linux_x86_64.tar.gz -C /usr/local/bin/ grpcurl
    rm grpcurl_1.8.7_linux_x86_64.tar.gz

    cat << 'EOF' > /tmp/task.proto
syntax = "proto3";
package task;

enum Priority {
  UNKNOWN = 0;
  LOW = 1;
  MEDIUM = 2;
  HIGH = 3;
}

message CreateTaskRequest {
  string title = 1;
  Priority priority = 2;
  repeated string tags = 3;
}

message TaskResponse {
  string id = 1;
  string status = 2;
}

service TaskService {
  rpc CreateTask(CreateTaskRequest) returns (TaskResponse);
}
EOF

    python3 -m grpc_tools.protoc -I/tmp --python_out=/tmp --grpc_python_out=/tmp /tmp/task.proto

    cat << 'EOF' > /tmp/server.py
import grpc
from concurrent import futures
import time
import task_pb2
import task_pb2_grpc
from grpc_reflection.v1alpha import reflection

class TaskServiceServicer(task_pb2_grpc.TaskServiceServicer):
    def CreateTask(self, request, context):
        if not request.title:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Missing title")
        if request.priority != task_pb2.HIGH:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Priority must be HIGH")
        if "automation" not in request.tags:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Missing 'automation' tag")

        return task_pb2.TaskResponse(id="task-999", status="CREATED_V2")

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    task_pb2_grpc.add_TaskServiceServicer_to_server(TaskServiceServicer(), server)
    SERVICE_NAMES = (
        task_pb2.DESCRIPTOR.services_by_name['TaskService'].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
