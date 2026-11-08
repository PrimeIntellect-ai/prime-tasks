#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the C source for the policy oracle
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <arpa/inet.h>

struct rule {
    uint32_t src_ip;
    uint32_t src_mask;
    uint32_t dst_ip;
    uint32_t dst_mask;
    int action;
    struct rule *next;
};

int parse_cidr(const char *cidr, uint32_t *ip, uint32_t *mask) {
    char ip_str[32];
    int prefix = 32;
    if (sscanf(cidr, "%[^/]/%d", ip_str, &prefix) == 1) {
        prefix = 32;
    }
    struct in_addr addr;
    if (inet_pton(AF_INET, ip_str, &addr) != 1) return 0;
    *ip = ntohl(addr.s_addr);
    *mask = prefix == 0 ? 0 : (~0U << (32 - prefix));
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    struct rule *head = NULL, *tail = NULL;
    char line[256];
    int rule_id;
    char src[64], dst[64], action[16];
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%d %s %s %s", &rule_id, src, dst, action) == 4) {
            struct rule *r = malloc(sizeof(struct rule));
            parse_cidr(src, &r->src_ip, &r->src_mask);
            parse_cidr(dst, &r->dst_ip, &r->dst_mask);
            r->action = (strcmp(action, "ALLOW") == 0) ? 1 : 0;
            r->next = NULL;
            if (!head) head = r;
            else tail->next = r;
            tail = r;
        }
    }
    fclose(f);

    char cmd[256];
    while (fgets(cmd, sizeof(cmd), stdin)) {
        char op[16], sip[64], dip[64];
        if (sscanf(cmd, "%s %s %s", op, sip, dip) == 3 && strcmp(op, "query") == 0) {
            uint32_t q_sip, q_sm, q_dip, q_dm;
            parse_cidr(sip, &q_sip, &q_sm);
            parse_cidr(dip, &q_dip, &q_dm);

            struct rule *curr = head;
            int counter = 0;
            int matched = 0;
            while (curr) {
                counter++;
                if ((q_sip & curr->src_mask) == (curr->src_ip & curr->src_mask) &&
                    (q_dip & curr->dst_mask) == (curr->dst_ip & curr->dst_mask)) {
                    printf("%s %dms\n", curr->action ? "ALLOW" : "DENY", counter);
                    matched = 1;
                    break;
                }
                curr = curr->next;
            }
            if (!matched) {
                printf("DENY %dms\n", counter);
            }
            fflush(stdout);
        }
    }
    return 0;
}
EOF

    # Compile and strip the oracle
    gcc -O2 /app/oracle.c -o /app/policy_oracle
    strip /app/policy_oracle
    rm /app/oracle.c

    # Generate base policies and traffic stats
    cat << 'EOF' > /home/user/generate_data.py
import random

rules = []
# Add some DENY rules that don't overlap with our ALLOWs
for i in range(1, 191):
    rules.append(f"{i} 10.0.{i}.0/24 10.1.{i}.0/24 DENY")

# Add ALLOW rules at the end
for i in range(191, 201):
    rules.append(f"{i} 192.168.{i-190}.0/24 10.2.0.0/16 ALLOW")

with open("/home/user/base_policies.txt", "w") as f:
    f.write("\n".join(rules) + "\n")

with open("/home/user/traffic_stats.csv", "w") as f:
    for i in range(191, 201):
        freq = (201 - i) * 100 
        f.write(f"192.168.{i-190}.1,10.2.0.1,{freq}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
