#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ tar
    pip3 install pytest

    mkdir -p /home/user/cloud_repo_temp
    cd /home/user/cloud_repo_temp
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo '{"instance_type": "t2.micro"}' > resource.json
    git add resource.json
    git commit -m "Initial commit"

    cd /home/user
    mkdir -p /home/user/tar_tmp
    mv /home/user/cloud_repo_temp /home/user/tar_tmp/cloud_repo
    tar -czf /home/user/cloud_backup.tar.gz -C /home/user/tar_tmp cloud_repo
    rm -rf /home/user/tar_tmp

    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>
#include <fstream>
#include <sys/stat.h>
#include <cstdlib>

int main() {
    struct stat info;
    if (stat("/home/user/cloud_repo", &info) != 0) {
        std::cerr << "Error: /home/user/cloud_repo does not exist. Missing dependency!" << std::endl;
        return 1;
    }

    std::ofstream report("/home/user/cost_report.txt");
    if (report.is_open()) {
        report << "ANALYSIS_COMPLETE" << std::endl;
        report.close();
        return 0;
    }
    return 1;
}
EOF

    cat << 'EOF' > /home/user/start_service.sh
#!/bin/bash
/home/user/analyzer
EOF
    chmod +x /home/user/start_service.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
