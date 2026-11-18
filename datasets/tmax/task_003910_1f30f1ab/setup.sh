#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl libssl-dev curl systemd wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/.config/systemd/user

    wget -q -O /home/user/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    cat << 'EOF' > /home/user/cost_api.cpp
#define CPPHTTPLIB_OPENSSL_SUPPORT
#include "httplib.h"
#include <fstream>
#include <iostream>

int main() {
    httplib::SSLServer svr("/home/user/cert.pem", "/home/user/key.pem");

    svr.Post("/report", [](const httplib::Request &req, httplib::Response &res) {
        std::ofstream log_file("/home/user/metrics.log");
        if (log_file.is_open()) {
            log_file << req.body;
            log_file.close();
            res.set_content("Success", "text/plain");
        } else {
            res.status = 500;
        }
    });

    svr.listen("127.0.0.1", 8443);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/reporter.sh
#!/bin/bash
sleep 2 # Ensure server has time to bind
curl -k -X POST https://127.0.0.1:8443/report -d '{"instance":"i-0abcd1234", "spot_price": 0.045, "region":"us-east-1"}'
EOF
    chmod +x /home/user/reporter.sh

    chmod -R 777 /home/user
