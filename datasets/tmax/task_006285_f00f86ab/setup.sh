#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ netcat-openbsd cron procps
    pip3 install pytest

    mkdir -p /home/user/workspace
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/workspace/proxy.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
    int sockfd;
    struct sockaddr_in servaddr, cliaddr, destaddr;

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = inet_addr("127.0.0.1");
    // BUG: wrong port
    servaddr.sin_port = htons(8081); 

    bind(sockfd, (const struct sockaddr *)&servaddr, sizeof(servaddr));

    memset(&destaddr, 0, sizeof(destaddr));
    destaddr.sin_family = AF_INET;
    destaddr.sin_port = htons(9090);
    destaddr.sin_addr.s_addr = inet_addr("127.0.0.1");

    char buffer[1024];
    while(true) {
        socklen_t len = sizeof(cliaddr);
        int n = recvfrom(sockfd, (char *)buffer, 1024, MSG_WAITALL, (struct sockaddr *) &cliaddr, &len);
        buffer[n] = '\0';

        // Remove trailing newlines for clean logging
        std::string msg(buffer);
        if (!msg.empty() && msg.back() == '\n') msg.pop_back();

        std::ofstream logfile("/home/user/logs/proxy.log", std::ios_base::app);
        logfile << "FORWARDED: " << msg << std::endl;
        logfile.close();

        sendto(sockfd, (const char *)buffer, n, MSG_CONFIRM, (const struct sockaddr *) &destaddr, sizeof(destaddr));
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/monitor.sh
#!/bin/bash
if ! pgrep -x "proxy" > /dev/null
then
    /home/user/workspace/proxy &
fi
EOF
    chmod +x /home/user/workspace/monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
