#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler
    pip3 install pytest

    mkdir -p /home/user/proto /home/user/nginx

    cat << 'EOF' > /home/user/proto/item.proto
syntax = "proto3";
package feature;
import "category.proto";

message Item {
    string id = 1;
    Category category = 2;
}

service FeatureService {
    rpc GetItem(Item) returns (Item);
}
EOF

    cat << 'EOF' > /home/user/proto/category.proto
syntax = "proto3";
package feature;
import "item.proto";

message Category {
    string name = 1;
    Item top_item = 2;
}
EOF

    cat << 'EOF' > /home/user/nginx/grpc.conf
server {
    listen 8080 http2;

    location /feature.FeatureService {
        proxy_pass http://localhost:50051;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
