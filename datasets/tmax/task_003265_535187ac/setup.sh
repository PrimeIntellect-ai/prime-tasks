#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make git tesseract-ocr imagemagick
    pip3 install pytest pandas pillow

    mkdir -p /home/user/uptime_analyzer
    mkdir -p /app

    # Create dashboard image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'REGION MONITOR: NA-WEST. EXPECTED UPTIME: 99.9%. TZ OFFSET: UTC-7. ALERTS CONFIGURED.', fill=(0,0,0))
img.save('/app/sre_dashboard.png')
"

    # Create golden report
    cat << 'EOF' > /opt/golden_uptime_report.csv
Date,Total_Uptime_Seconds,Downtime_Events
2023-10-01,86400,0
2023-10-02,86000,1
EOF

    # Create encrypted log
    cat << 'EOF' > /home/user/system_events.enc.log
2023-10-01T00:00:00Z UP
2023-10-02T00:00:00Z DOWN
2023-10-02T00:06:40Z UP
EOF

    # Setup git repo
    cd /home/user/uptime_analyzer
    git init
    git config user.name "SRE"
    git config user.email "sre@example.com"

    # Create Makefile
    cat << 'EOF' > Makefile
uptime_bin: analyzer.cpp
	g++ -O2 -std=c++11 analyzer.cpp -o uptime_bin
EOF

    # Create analyzer.cpp with bugs
    cat << 'EOF' > analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdlib>
#include <cassert>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <input> <output>\n";
        return 1;
    }

    char* key = getenv("DECRYPT_KEY");
    if (!key || string(key) != "SRE_PROD_8831_XYZ") {
        throw runtime_error("Invalid or missing DECRYPT_KEY");
    }

    // Dummy logic for the agent to fix
    int end_bucket = 100;
    int timestamp = 50;
    if (timestamp < end_bucket) {
        // off by one bug
    }

    string log = "  UTC";
    assert(log.find("  ") == string::npos); // assertion failure on double space

    // Write dummy output for now
    ofstream out(argv[2]);
    out << "Date,Total_Uptime_Seconds,Downtime_Events\n";
    out << "2023-10-01,86400,0\n";
    out << "2023-10-02,86000,1\n";
    out.close();

    return 0;
}
EOF

    # Commit 1
    git add Makefile analyzer.cpp
    git commit -m "Initial commit"

    # Commit 2 (with secret)
    cat << 'EOF' > secret.h
const string key = "SRE_PROD_8831_XYZ";
EOF
    git add secret.h
    git commit -m "Add secret key"

    # Commit 3 (remove secret)
    git rm secret.h
    git commit -m "Remove secret key"

    # Commit 4 (refactor)
    echo "// refactored" >> analyzer.cpp
    git add analyzer.cpp
    git commit -m "Refactor analyzer"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
