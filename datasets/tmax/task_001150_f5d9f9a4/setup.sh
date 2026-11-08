#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc locales tzdata
    pip3 install pytest pexpect

    # Generate locales
    sed -i '/de_DE.UTF-8/s/^# //g' /etc/locale.gen
    locale-gen
    # Create specific locale name to satisfy the test's exact string match
    localedef -i de_DE -c -f UTF-8 /usr/lib/locale/de_DE.utf-8 || true

    mkdir -p /app

    # Create the legacy deploy script
    cat << 'EOF' > /app/legacy_deploy.sh
#!/bin/bash
echo "Starting deployment wizard..."
read -p "Enter target deployment tier: " tier
if [ "$tier" != "staging" ]; then echo "Invalid tier"; exit 1; fi

read -p "Enter system timezone for logs: " tz_input
if [ "$TZ" != "$tz_input" ]; then echo "Environment TZ variable does not match input!"; exit 1; fi

read -p "Enter expected system locale: " lang_input
if [ "$LANG" != "$lang_input" ]; then echo "Environment LANG variable does not match input!"; exit 1; fi

read -p "Proceed with rolling restart? (yes/no): " proceed
if [ "$proceed" == "yes" ]; then
    echo "Deployment successful"
    exit 0
else
    echo "Aborted."
    exit 1
fi
EOF
    chmod +x /app/legacy_deploy.sh

    # Create the C source for the auth_signer
    cat << 'EOF' > /tmp/auth_signer.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <locale.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    setenv("TZ", "Europe/Berlin", 1);
    tzset();
    setlocale(LC_ALL, "de_DE.UTF-8");

    time_t t = atol(argv[1]);
    struct tm *tm_info = localtime(&t);

    char buffer[256];
    strftime(buffer, 256, "Wartungsfenster: %A, %d. %B %Y - %H:%M:%S (%Z)", tm_info);
    printf("%s\n", buffer);

    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /tmp/auth_signer.c -o /app/auth_signer
    strip /app/auth_signer
    rm /tmp/auth_signer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
