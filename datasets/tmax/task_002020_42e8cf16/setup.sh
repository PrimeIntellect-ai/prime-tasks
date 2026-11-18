#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect curl systemd dbus openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    mkdir -p /home/user/public_html
    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/users.db
alice:x:1001
bob:x:1002
EOF

    cat << 'EOF' > /home/user/interactive_admin.sh
#!/bin/bash
read -p "Enter new username: " uname
read -s -p "Enter password: " pass
echo ""
echo "$uname:x:$((1000 + $RANDOM % 1000))" >> /home/user/users.db
echo "User added."
EOF
    chmod +x /home/user/interactive_admin.sh

    cat << 'EOF' > /home/user/account_monitor.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *db = fopen("users.db", "r");
    if (!db) {
        perror("Failed to open users.db");
        return 1;
    }

    FILE *html = fopen("public_html/report.html", "w");
    if (!html) {
        perror("Failed to open report.html");
        fclose(db);
        return 1;
    }

    fprintf(html, "<html><body><h1>User Report</h1><ul>\n");
    char line[256];
    while (fgets(line, sizeof(line), db)) {
        fprintf(html, "<li>%s</li>\n", line);
    }
    fprintf(html, "</ul></body></html>\n");

    fclose(html);
    fclose(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
