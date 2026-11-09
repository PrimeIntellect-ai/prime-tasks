#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_project

    cat << 'EOF' > /home/user/legacy_project/vulnerable_service.proto
// Version: 1.9.5
syntax = "proto3";
package legacy;
service OldService {
  rpc DoThing (Empty) returns (Empty);
}
message Empty {}
EOF

    cat << 'EOF' > /home/user/legacy_project/secure_service.proto
// Version: 2.1.2
syntax = "proto3";
package auth;
service AuthService {
  rpc VerifyToken (TokenRequest) returns (TokenResponse);
}
message TokenRequest {
  string token = 1;
}
message TokenResponse {
  bool valid = 1;
}
EOF

    cat << 'EOF' > /home/user/legacy_project/auth_logic.rb
def verify_token(token)
  if token.nil? || token.empty?
    return false
  end
  # Must start with SECURE-, be at least 15 chars long, and not contain "DROP"
  if token.start_with?("SECURE-") && token.length >= 15 && !token.include?("DROP")
    return true
  end
  return false
end
EOF

    chown -R user:user /home/user/legacy_project
    chmod -R 777 /home/user
