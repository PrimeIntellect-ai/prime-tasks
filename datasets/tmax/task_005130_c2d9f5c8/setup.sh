#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc make
    pip3 install pytest grpcio grpcio-tools Pillow

    mkdir -p /app/dep_resolver /app/proto

    # Create image with text
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'LEGACY ARCHITECTURE NOTE'" \
        -draw "text 10,60 'Make sure to use the correct token for the microservice.'" \
        -draw "text 10,90 'TOKEN: S3cr3t_CI_882'" /app/pipeline_specs.png

    # Create C file
    cat << 'EOF' > /app/dep_resolver/resolve.c
#include <math.h>
#include <string.h>

int validate_graph(const char* pkg, const char* ver) {
    double x = sqrt(16.0);
    if (x == 4.0 && strcmp(pkg, "lib-core") == 0) {
        return 1;
    }
    return 0;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/dep_resolver/Makefile
all: libresolver.so
libresolver.so: resolve.o
	gcc -shared -o libresolver.so resolve.o
resolve.o: resolve.c
	gcc -c -fPIC resolve.c
EOF

    # Create Python gRPC server
    cat << 'EOF' > /app/server.py
import os
import sys
import time
import ctypes
from concurrent import futures
import grpc

sys.path.append('/app')
import resolver_pb2
import resolver_pb2_grpc

class DependencyResolverServicer(resolver_pb2_grpc.DependencyResolverServicer):
    def ResolveGraph(self, request, context):
        token = os.environ.get("GRPC_AUTH_TOKEN", "")
        metadata = dict(context.invocation_metadata())
        expected_auth = f"Bearer {token}"

        if metadata.get("authorization") != expected_auth:
            context.abort(grpc.StatusCode.UNAUTHENTICATED, "Invalid token")

        lib = ctypes.CDLL("/app/dep_resolver/libresolver.so")
        is_valid = lib.validate_graph(request.package_name.encode('utf-8'), request.current_version.encode('utf-8'))

        return resolver_pb2.ResolveResponse(
            is_valid=bool(is_valid),
            resolved_tree=f"{request.package_name}@{request.current_version}->deps@ok" if is_valid else "invalid"
        )

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    resolver_pb2_grpc.add_DependencyResolverServicer_to_server(DependencyResolverServicer(), server)
    server.add_insecure_port('[::]:50505')
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
    chmod -R 777 /app
    chmod -R 777 /home/user
