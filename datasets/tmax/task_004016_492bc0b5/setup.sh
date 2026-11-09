#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl wget protobuf-compiler
pip3 install pytest grpcio grpcio-tools

wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
tar -xvf grpcurl_1.8.7_linux_x86_64.tar.gz
mv grpcurl /usr/local/bin/
rm grpcurl_1.8.7_linux_x86_64.tar.gz

mkdir -p /home/user

cat << 'EOF' > /home/user/check_system.sh
#!/bin/bash
echo "Checking system status..."
curl -s http://api.legacy.local/v1/status
EOF
chmod +x /home/user/check_system.sh

mkdir -p /tmp/hidden_proto
cat << 'EOF' > /tmp/hidden_proto/system.proto
syntax = "proto3";
service System {
  rpc GetStatus (StatusRequest) returns (StatusResponse);
}
message StatusRequest {}
message StatusResponse {
  string status = 1;
}
EOF

python3 -m grpc_tools.protoc -I/tmp/hidden_proto --python_out=/home/user --grpc_python_out=/home/user /tmp/hidden_proto/system.proto

cat << 'EOF' > /home/user/mock_server.py
import grpc
from concurrent import futures
import time
import system_pb2
import system_pb2_grpc

class SystemServicer(system_pb2_grpc.SystemServicer):
    def GetStatus(self, request, context):
        return system_pb2.StatusResponse(status="ALL_SYSTEMS_NOMINAL")

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    system_pb2_grpc.add_SystemServicer_to_server(SystemServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    try:
        while True:
            time.sleep(86400)
    except KeyboardInterrupt:
        server.stop(0)

if __name__ == '__main__':
    serve()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
