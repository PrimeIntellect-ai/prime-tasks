#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ socat logrotate tar file
pip3 install pytest

mkdir -p /home/user/setup_tmp
cd /home/user/setup_tmp

# Create the buggy C++ daemon
cat << 'EOF' > metrics_daemon.cpp
#include <iostream>
#include <fstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>

int main() {
    int server_fd, client_fd;
    struct sockaddr_un server_addr;

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        return 1;
    }

    server_addr.sun_family = AF_UNIX;
    // BUG: Obsolete path
    strcpy(server_addr.sun_path, "/home/user/old.sock");
    unlink(server_addr.sun_path);

    if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        return 1;
    }

    listen(server_fd, 5);

    client_fd = accept(server_fd, NULL, NULL);
    if (client_fd >= 0) {
        char buffer[256];
        int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
        if (bytes_read > 0) {
            buffer[bytes_read] = '\0';
            std::ofstream log_file("/home/user/app_metrics.log", std::ios::app);
            log_file << buffer << std::endl;
        }
        close(client_fd);
    }
    close(server_fd);
    unlink(server_addr.sun_path);
    return 0;
}
EOF

# Create the test script
cat << 'EOF' > send_test.sh
#!/bin/bash
# Simulates legacy CI restoring pipeline test
echo "TEST_RESTORE_METRIC: SUCCESS_42" | socat - TCP:localhost:9999
EOF

chmod +x send_test.sh

# Archive and cleanup
tar -czf /home/user/backup_archive.tar.gz metrics_daemon.cpp send_test.sh
cd /home/user
rm -rf /home/user/setup_tmp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
