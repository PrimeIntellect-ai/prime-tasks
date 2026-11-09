#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/edge_proxy/logs
    mkdir -p /home/user/run

    cat << 'EOF' > /home/user/edge_proxy/nginx.conf
http {
    upstream backend {
        server unix:/tmp/backend.sock;
    }
    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
        }
    }
}
events {}
EOF

    cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash
echo "Monitoring..."
EOF
    chmod +x /home/user/monitor.sh

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_encoder.cpp
#include <iostream>
#include <cstdint>

int main() {
    uint32_t T, H, P, L;
    if (!(std::cin >> T >> H >> P >> L)) return 1;

    uint8_t checksum = (T + H + P + L) & 0xFF;
    uint8_t flag = (T > 30) ? 1 : 0;

    uint8_t out[16];
    out[0] = 0xAA;
    out[1] = 0xBB;
    out[2] = checksum;
    out[3] = flag;
    out[4] = T & 0xFF;
    out[5] = (T >> 8) & 0xFF;
    out[6] = H & 0xFF;
    out[7] = (H >> 8) & 0xFF;
    out[8] = P & 0xFF;
    out[9] = (P >> 8) & 0xFF;
    out[10] = L & 0xFF;
    out[11] = (L >> 8) & 0xFF;
    out[12] = 0x00;
    out[13] = 0x00;
    out[14] = 0xCC;
    out[15] = 0xDD;

    std::cout.write(reinterpret_cast<char*>(out), 16);
    return 0;
}
EOF
    g++ -O2 /tmp/legacy_encoder.cpp -o /app/legacy_encoder
    strip /app/legacy_encoder
    chmod +x /app/legacy_encoder
    rm /tmp/legacy_encoder.cpp

    chown -R user:user /home/user
    chmod -R 777 /home/user
