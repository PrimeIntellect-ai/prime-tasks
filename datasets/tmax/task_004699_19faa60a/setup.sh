#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang protobuf-compiler
    pip3 install pytest

    mkdir -p /home/user/protos
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/protos/service_1.5.9.proto
syntax = "proto3";
package datapipeline;
option go_package = "pipeline/api";

service DataProcessor {
  rpc Process(ProcessRequest) returns (ProcessResponse);
}
message ProcessRequest {}
message ProcessResponse {}
EOF

    cat << 'EOF' > /home/user/protos/service_1.12.0.proto
syntax = "proto3";
package datapipeline;
option go_package = "pipeline/api";

service DataProcessor {
  rpc Process(ProcessRequest) returns (ProcessResponse);
}
message ProcessRequest {}
message ProcessResponse {}
EOF

    cat << 'EOF' > /home/user/protos/service_2.0.1-rc.1.proto
syntax = "proto3";
package datapipeline;
option go_package = "pipeline/api";

service DataProcessor {
  rpc Process(ProcessRequest) returns (ProcessResponse);
}
message ProcessRequest {}
message ProcessResponse {}
EOF

    cat << 'EOF' > /home/user/protos/service_2.0.1.proto
syntax = "proto3";
package datapipeline;
option go_package = "pipeline/api";

service DataProcessor {
  rpc Process(ProcessRequest) returns (ProcessResponse);
}
message ProcessRequest {}
message ProcessResponse {}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
