#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/protos

    cat << 'EOF' > /home/user/protos/auth.proto
syntax = "proto3";
package auth;
service AuthService {}
EOF

    cat << 'EOF' > /home/user/protos/db.proto
syntax = "proto3";
package db;
service DBService {}
EOF

    cat << 'EOF' > /home/user/protos/user.proto
syntax = "proto3";
package user;
import "auth.proto";
import "db.proto";
service UserService {}
EOF

    cat << 'EOF' > /home/user/protos/notification.proto
syntax = "proto3";
package notification;
import "user.proto";
service NotificationService {}
EOF

    cat << 'EOF' > /home/user/protos/payment.proto
syntax = "proto3";
package payment;
import "user.proto";
import "db.proto";
service PaymentService {}
EOF

    cat << 'EOF' > /home/user/protos/gateway.proto
syntax = "proto3";
package gateway;
import "payment.proto";
import "notification.proto";
import "auth.proto";
service GatewayService {}
EOF

    chmod -R 777 /home/user
