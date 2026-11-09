#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ libcurl4-openssl-dev curl
    pip3 install pytest numpy matplotlib

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # Generate raw data and truth data
    python3 -c "
import json, numpy as np
np.random.seed(42)
raw = np.random.normal(0, 5, 1000)
# Inject missing values
missing_indices = np.random.choice(1000, 50, replace=False)
raw[missing_indices] = -9999.0
# Inject outliers
outlier_indices = np.random.choice(1000, 20, replace=False)
raw[outlier_indices] = np.random.choice([-15.0, 20.0, 50.0], 20)

valid_mean = np.mean(raw[raw != -9999.0])
truth = np.copy(raw)
truth[truth == -9999.0] = valid_mean
truth = np.clip(truth, -10.0, 10.0)

with open('/home/user/pipeline/raw_data.json', 'w') as f:
    json.dump(raw.tolist(), f)

np.savetxt('/home/user/pipeline/.truth_data.csv', truth, fmt='%.4f')
"

    # Raw Data Server
    cat << 'EOF' > /home/user/pipeline/raw_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with open('/home/user/pipeline/raw_data.json', 'r') as f:
                self.wfile.write(f.read().encode())
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    # Initial processor.cpp template
    cat << 'EOF' > /home/user/pipeline/processor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <curl/curl.h>

// Note: Parse JSON here and implement data processing
// Write to cleaned_data.csv

int main() {
    // Boilerplate C++ HTTP GET omitted for brevity, assume agent writes or uses a provided header
    std::cout << "Implement fetch, missing value imputation, outlier clamping, and write to CSV." << std::endl;
    return 0;
}
EOF

    # Reporting service script
    cat << 'EOF' > /home/user/pipeline/report.py
import matplotlib.pyplot as plt
import numpy as np

try:
    data = np.loadtxt('/home/user/pipeline/cleaned_data.csv')
    plt.plot(data)
    plt.title('Cleaned Data')
    plt.savefig('/home/user/pipeline/report.png')
except Exception as e:
    print(f"Error: {e}")
EOF

    cat << 'EOF' > /home/user/pipeline/start_report_service.sh
#!/bin/bash
# Missing MPLBACKEND=Agg here
python3 /home/user/pipeline/report.py
EOF
    chmod +x /home/user/pipeline/start_report_service.sh

    # Setup services to start on shell login
    echo "python3 /home/user/pipeline/raw_server.py > /dev/null 2>&1 &" >> /home/user/.bashrc
    echo "redis-server --daemonize yes > /dev/null 2>&1" >> /home/user/.bashrc

    echo "python3 /home/user/pipeline/raw_server.py > /dev/null 2>&1 &" >> /root/.bashrc
    echo "redis-server --daemonize yes > /dev/null 2>&1" >> /root/.bashrc

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
