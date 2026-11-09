#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest grpcio grpcio-tools

    # Create directories
    mkdir -p /home/user/proto_deps/api/v1
    mkdir -p /home/user/proto_deps/core/v1
    mkdir -p /home/user/proto_deps/auth/v2
    mkdir -p /home/user/proto_deps/common/v1

    # Create common/v1/types.proto
    cat << 'EOF' > /home/user/proto_deps/common/v1/types.proto
syntax = "proto3";
package common.v1;
message Status {
  int32 code = 1;
}
EOF

    # Create core/v1/user.proto
    cat << 'EOF' > /home/user/proto_deps/core/v1/user.proto
syntax = "proto3";
package core.v1;
message UserRequest {
  string user_id = 1;
}
EOF

    # Create auth/v2/token.proto with BUG (imports common/v2 instead of common/v1)
    cat << 'EOF' > /home/user/proto_deps/auth/v2/token.proto
syntax = "proto3";
package auth.v2;
import "common/v2/types.proto";

message TokenResponse {
  string token = 1;
}
EOF

    # Create api/v1/gateway.proto
    cat << 'EOF' > /home/user/proto_deps/api/v1/gateway.proto
syntax = "proto3";
package api.v1;

import "core/v1/user.proto";
import "auth/v2/token.proto";

service Gateway {
  rpc GetUserToken(core.v1.UserRequest) returns (auth.v2.TokenResponse);
}
EOF

    # Create the patch file
    cat << 'EOF' > /home/user/fix_imports.patch
--- auth/v2/token.proto
+++ auth/v2/token.proto
@@ -2,6 +2,6 @@
 package auth.v2;
-import "common/v2/types.proto";
+import "common/v1/types.proto";

 message TokenResponse {
   string token = 1;
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
