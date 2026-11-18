#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/grpc_project

    cat << 'EOF' > /home/user/grpc_project/math_basic.proto
syntax = "proto3";
package math.basic;

service MathService {
  rpc Add (AddRequest) returns (AddResponse);
}
EOF

    cat << 'EOF' > /home/user/grpc_project/hamming_encoder.proto
syntax = "proto3";
package telecom.ecc.v1;

service ErrorCorrection {
  rpc EncodeHamming (DataRequest) returns (DataResponse);
}
EOF

    cat << 'EOF' > /home/user/grpc_project/file_verifier.proto
syntax = "proto3";
package storage.verification;

service FileVerifier {
  rpc CalculateChecksum (FileRequest) returns (HashResponse);
}
EOF

    cat << 'EOF' > /home/user/grpc_project/random_stuff.proto
syntax = "proto3";
package random.stuff;

// Just a random comment mentioning hamming, wait no, lowercase doesn't match!
service RandomService {
  rpc DoNothing (Empty) returns (Empty);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
