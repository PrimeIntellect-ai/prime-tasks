#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/hidden_flag.txt
FLAG{c0mm4nd_1nj3ct10n_m4st3r}
EOF

cat << 'EOF' > /home/user/vulnerable_reporter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int check_token(const char* token) {
    // Basic obfuscation: token must match "T0k3n_G3n!" 
    // but checked via weak logic to simulate an audit finding.
    const char* expected = "T0k3n_G3n!";
    if (strlen(token) != strlen(expected)) return 0;
    for (int i = 0; i < strlen(expected); i++) {
        if (token[i] != expected[i]) return 0;
    }
    return 1;
}

int main(int argc, char** argv) {
    char* token = getenv("AUTH_TOKEN");
    if (!token || !check_token(token)) {
        printf("Error: Invalid or missing AUTH_TOKEN.\n");
        return 1;
    }
    if (argc < 2) {
        printf("Usage: %s <report_text>\n", argv[0]);
        return 1;
    }

    char cmd[512];
    // Vulnerable to command injection (and XSS if viewed in browser)
    snprintf(cmd, sizeof(cmd), "echo '<div>%s</div>' >> /home/user/report.html", argv[1]);
    system(cmd);

    printf("Report updated.\n");
    return 0;
}
EOF

gcc /home/user/vulnerable_reporter.c -o /home/user/vulnerable_reporter

chmod -R 777 /home/user
chmod 644 /home/user/hidden_flag.txt
chmod +x /home/user/vulnerable_reporter
