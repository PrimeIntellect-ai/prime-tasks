#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gawk sed
    pip3 install pytest

    mkdir -p /home/user/legacy_app

    cat << 'EOF' > /home/user/legacy_app/schema.proto
syntax = "proto2";

message DataRequest {
  required string payload = 1;
}

message DataResponse {
  required string result = 1;
}

service DataProcessor {
  rpc ProcessData (DataRequest) returns (DataResponse);
}
EOF

    cat << 'EOF' > /home/user/legacy_app/service.py
import time
import BaseHTTPServer
import urlparse
import threading
import grpc
from concurrent import futures

import schema_pb2
import schema_pb2_grpc

class DataProcessorServicer(schema_pb2_grpc.DataProcessorServicer):
    def ProcessData(self, request, context):
        print "Processing payload: " + request.payload
        return schema_pb2.DataResponse(result="Processed: " + request.payload)

class HTTPHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse.urlparse(self.path)
        if parsed_path.path == "/process":
            query = urlparse.parse_qs(parsed_path.query)
            payload = query.get('payload', [''])[0]

            # Local gRPC call
            channel = grpc.insecure_channel('localhost:50051')
            stub = schema_pb2_grpc.DataProcessorStub(channel)
            response = stub.ProcessData(schema_pb2.DataRequest(payload=payload))

            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(response.result.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def serve():
    grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    schema_pb2_grpc.add_DataProcessorServicer_to_server(DataProcessorServicer(), grpc_server)
    grpc_server.add_insecure_port('[::]:50051')
    grpc_server.start()

    http_server = BaseHTTPServer.HTTPServer(('', 8080), HTTPHandler)

    # Run HTTP server in a separate thread
    threading.Thread(target=http_server.serve_forever).start()

    try:
        while True:
            time.sleep(86400)
    except KeyboardInterrupt:
        grpc_server.stop(0)
        http_server.shutdown()

if __name__ == '__main__':
    serve()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
