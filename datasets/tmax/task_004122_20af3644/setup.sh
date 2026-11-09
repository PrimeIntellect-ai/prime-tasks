#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc binutils
    pip3 install --default-timeout=100 pytest

    mkdir -p /home/user /app

    cat << 'EOF' > /home/user/user_roles.csv
user_id,role_name
alice,finance_manager
bob,clerk
charlie,it_admin
diana,accounts_payable
EOF

    cat << 'EOF' > /home/user/role_hierarchy.csv
parent,child
finance_manager,finance_staff
finance_manager,APPROVE_TRANSFER
finance_staff,clerk
finance_staff,FUNDS_TRANSFER
clerk,VIEW_LEDGER
clerk,GENERATE_REPORT
it_admin,CREATE_VENDOR
it_admin,MANAGE_USERS
accounts_payable,CREATE_VENDOR
accounts_payable,PAY_VENDOR
EOF

    cat << 'EOF' > /tmp/sod_oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    int has_funds = 0, has_approve = 0;
    int has_create_v = 0, has_pay_v = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "FUNDS_TRANSFER") == 0) has_funds = 1;
        if (strcmp(argv[i], "APPROVE_TRANSFER") == 0) has_approve = 1;
        if (strcmp(argv[i], "CREATE_VENDOR") == 0) has_create_v = 1;
        if (strcmp(argv[i], "PAY_VENDOR") == 0) has_pay_v = 1;
    }

    if (has_funds && has_approve) {
        printf("TOXIC: FUNDS_TRANSFER, APPROVE_TRANSFER\n");
        return 1;
    }
    if (has_create_v && has_pay_v) {
        printf("TOXIC: CREATE_VENDOR, PAY_VENDOR\n");
        return 1;
    }

    printf("SAFE\n");
    return 0;
}
EOF

    gcc -O2 /tmp/sod_oracle.c -o /app/sod_oracle
    strip /app/sod_oracle
    chmod +x /app/sod_oracle
    rm /tmp/sod_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
