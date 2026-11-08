#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect acl gcc tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create the mock tarball
    mkdir -p mock_tar_contents/postfix mock_tar_contents/dovecot
    echo "smtpd_banner = \$myhostname ESMTP" > mock_tar_contents/postfix/main.cf
    echo "listen = *" > mock_tar_contents/dovecot/dovecot.conf
    cd mock_tar_contents
    tar -cf /home/user/mock_backup.tar *
    cd ..
    rm -rf mock_tar_contents

    # Write the mock backup fetcher in C
    cat << 'C_EOF' > /home/user/fetch_backup.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    char password[256];
    printf("Password for backup server: ");
    fflush(stdout);

    if (fgets(password, sizeof(password), stdin) != NULL) {
        password[strcspn(password, "\n")] = 0; // strip newline
        if (strcmp(password, "SecureRest0re!") == 0) {
            printf("\nAuthentication successful. Downloading...\n");
            system("cp /home/user/mock_backup.tar /home/user/mail_data.tar");
            printf("Download complete: mail_data.tar\n");
            return 0;
        } else {
            printf("\nPermission denied, please try again.\n");
            return 1;
        }
    }
    return 1;
}
C_EOF

    gcc /home/user/fetch_backup.c -o /home/user/fetch_backup
    rm /home/user/fetch_backup.c

    chmod -R 777 /home/user
