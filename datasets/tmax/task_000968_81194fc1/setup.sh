#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    mkdir -p /home/user/mail_spool

    cat << 'EOF' > /home/user/project/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

bool isValidEmail(const std::string& email) {
    int at_count = 0;
    for (size_t i = 0; i <= email.length(); ++i) { // BUG: accessing email[email.length()] causes issues in some contexts, or we can use a null pointer dereference
        if (email[i] == '@') at_count++;
    }
    // Intentional crash:
    char* crash = nullptr;
    if (at_count == 0) {
        *crash = 'x';
    }
    return at_count == 1;
}

int main() {
    std::ifstream infile("/home/user/project/emails.txt");
    std::ofstream outfile("/home/user/project/valid_emails.txt");
    std::string line;
    while (std::getline(infile, line)) {
        if (isValidEmail(line)) {
            outfile << line << std::endl;
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/emails.txt
admin@example.com
invalid-email
user@domain.com
double@@domain.com
EOF

    cat << 'EOF' > /home/user/ci_daemon.sh
#!/bin/bash
# Missing set -e, syntax error in if statement

echo "Starting CI Pipeline"

g++ /home/user/project/main.cpp -o /home/user/project/app
/home/user/project/app

if [ -f /home/user/project/valid_emails.txt ]
    echo "Emails processed." # BUG: missing 'then'
fi

/home/user/backup.sh /home/user/project

echo "BUILD SUCCESS" > /home/user/mail_spool/notification.txt
EOF

    chmod +x /home/user/ci_daemon.sh
    chmod -R 777 /home/user
