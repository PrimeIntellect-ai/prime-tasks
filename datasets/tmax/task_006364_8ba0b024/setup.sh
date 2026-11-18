#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies
    apt-get install -y g++ make protobuf-compiler protobuf-compiler-grpc libgrpc++-dev pkg-config wget tar

    # Install grpcurl
    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
    tar -xvf grpcurl_1.8.7_linux_x86_64.tar.gz
    mv grpcurl /usr/local/bin/
    rm grpcurl_1.8.7_linux_x86_64.tar.gz

    # Create directories
    mkdir -p /home/user/waf_pr
    cd /home/user/waf_pr

    # Create waf.proto
    cat << 'EOF' > waf.proto
syntax = "proto3";
package waf;

service WafService {
  rpc EvaluateRisk (RiskRequest) returns (RiskResponse) {}
}

enum Action {
  UNKNOWN = 0;
  ALLOW = 1;
  CHALLENGE = 2;
  BLOCK = 3;
}

message RiskRequest {
  int32 total_requests = 1;
  int32 time_window_seconds = 2;
  int32 failed_logins = 3;
  float ip_trust_score = 4;
}

message RiskResponse {
  Action action = 1;
  float risk_score = 2;
}
EOF

    # Create waf_service.cpp
    cat << 'EOF' > waf_service.cpp
#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "waf.grpc.pb.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using waf::WafService;
using waf::RiskRequest;
using waf::RiskResponse;
using waf::Action;

class WafServiceImpl final : public WafService::Service {
  Status EvaluateRisk(ServerContext* context, const RiskRequest* request,
                      RiskResponse* reply) override {

    // BUG: Integer division
    float request_rate = request->total_requests() / request->time_window_seconds();

    float risk_score = (request_rate * 1.5) + (request->failed_logins() * 10.0);
    reply->set_risk_score(risk_score);

    // BUG: Incomplete constraint satisfaction
    if (risk_score > 50.0) {
      reply->set_action(waf::BLOCK);
    } else {
      reply->set_action(waf::ALLOW);
    }

    return Status::OK;
  }
};

void RunServer() {
  std::string server_address("0.0.0.0:50051");
  WafServiceImpl service;

  ServerBuilder builder;
  builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
  builder.RegisterService(&service);
  std::unique_ptr<Server> server(builder.BuildAndStart());
  std::cout << "Server listening on " << server_address << std::endl;
  server->Wait();
}

int main(int argc, char** argv) {
  RunServer();
  return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > Makefile
LDFLAGS = -L/usr/local/lib `pkg-config --libs protobuf grpc++ grpc` -Wl,--no-as-needed -lgrpc++_reflection -Wl,--as-needed -ldl
CXX = g++
CPPFLAGS += `pkg-config --cflags protobuf grpc`
CXXFLAGS += -std=c++17

all: waf_server

# BUG: Missing grpc_cpp_plugin in protoc invocation
waf.pb.cc waf.pb.h waf.grpc.pb.cc waf.grpc.pb.h: waf.proto
	protoc --cpp_out=. waf.proto

waf_server: waf.pb.o waf.grpc.pb.o waf_service.o
	$(CXX) $^ $(LDFLAGS) -o $@

clean:
	rm -f *.o *.pb.cc *.pb.h waf_server
EOF

    # Create test_integration.sh
    cat << 'EOF' > test_integration.sh
#!/bin/bash
sleep 2 # wait for server to start

echo "Test 1: BLOCK" > /home/user/waf_pr/results.log
grpcurl -plaintext -d '{"total_requests": 100, "time_window_seconds": 2, "failed_logins": 0, "ip_trust_score": 0.9}' localhost:50051 waf.WafService/EvaluateRisk | grep -o 'action": "[A-Z]*"' >> /home/user/waf_pr/results.log

echo "Test 2: ALLOW" >> /home/user/waf_pr/results.log
grpcurl -plaintext -d '{"total_requests": 10, "time_window_seconds": 3, "failed_logins": 0, "ip_trust_score": 0.9}' localhost:50051 waf.WafService/EvaluateRisk | grep -o 'action": "[A-Z]*"' >> /home/user/waf_pr/results.log

echo "Test 3: CHALLENGE" >> /home/user/waf_pr/results.log
grpcurl -plaintext -d '{"total_requests": 10, "time_window_seconds": 3, "failed_logins": 0, "ip_trust_score": 0.1}' localhost:50051 waf.WafService/EvaluateRisk | grep -o 'action": "[A-Z]*"' >> /home/user/waf_pr/results.log
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
