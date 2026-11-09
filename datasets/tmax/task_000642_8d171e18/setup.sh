#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation/tokens
    cd /home/user/investigation

    # 1. Create sshd_config
    cat << 'EOF' > sshd_config
Port 22
ListenAddress 0.0.0.0
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/libexec/openssh/sftp-server
Port 31337
EOF

    # 2. Create authorized_keys
    cat << 'EOF' > authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3X... admin_user_key
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... backup_service
ssh-dss AAAAB3NzaC1kc3MAAACBAPv... backdoor_access_99x
EOF

    # 3. Generate CA and Tokens
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.pem -days 365 -nodes -subj "/CN=AttackerCA"

    # Alpha: Invalid (self-signed)
    openssl req -x509 -newkey rsa:2048 -keyout alpha.key -out tokens/token_alpha.pem -days 365 -nodes -subj "/CN=Alpha"

    # Beta: Valid (signed by CA)
    openssl req -newkey rsa:2048 -keyout beta.key -out beta.csr -nodes -subj "/CN=Beta"
    openssl x509 -req -in beta.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out tokens/token_beta.pem -days 365

    # Gamma: Invalid (signed by different fake CA)
    openssl req -x509 -newkey rsa:2048 -keyout fake_ca.key -out fake_ca.pem -days 365 -nodes -subj "/CN=FakeCA"
    openssl req -newkey rsa:2048 -keyout gamma.key -out gamma.csr -nodes -subj "/CN=Gamma"
    openssl x509 -req -in gamma.csr -CA fake_ca.pem -CAkey fake_ca.key -CAcreateserial -out tokens/token_gamma.pem -days 365

    rm -f *.key *.csr *.srl

    # 4. Create vulnerable validator.c
    cat << 'EOF' > validator.c
#include <stdio.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <openssl/pem.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("Usage: %s <token.pem>\n", argv[0]);
        return 1;
    }

    OpenSSL_add_all_algorithms();

    X509_STORE *store = X509_STORE_new();
    X509_LOOKUP *lookup = X509_STORE_add_lookup(store, X509_LOOKUP_file());
    X509_LOOKUP_load_file(lookup, "/home/user/investigation/ca.pem", X509_FILETYPE_PEM);

    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        printf("Cannot open token file\n");
        return 1;
    }
    X509 *cert = PEM_read_X509(fp, NULL, 0, NULL);
    fclose(fp);

    X509_STORE_CTX *ctx = X509_STORE_CTX_new();
    X509_STORE_CTX_init(ctx, store, cert, NULL);

    int result = X509_verify_cert(ctx);

    // VULNERABILITY: Returns >= 0 instead of == 1
    if (result >= 0) {
        printf("VALID\n");
        return 0;
    } else {
        printf("INVALID\n");
        return 1;
    }
}
EOF

    chown -R user:user /home/user/investigation
    chmod -R 777 /home/user
