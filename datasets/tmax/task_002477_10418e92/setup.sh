#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    mkdir -p /app
    mkdir -p /etc/vault
    chmod 777 /etc/vault

    # Create mock whisper-cli
    cat << 'EOF' > /usr/local/bin/whisper-cli
#!/bin/bash
echo "The package will be delivered at midnight by the eastern docks."
EOF
    chmod +x /usr/local/bin/whisper-cli

    # Create vault_decrypt.c
    cat << 'EOF' > /app/vault_decrypt.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.enc> <output.wav>\n", argv[0]);
        return 1;
    }

    if (getuid() == 0) {
        printf("Error: Cannot run as root.\n");
        return 1;
    }

    struct stat st;
    if (stat("/etc/vault/key.pem", &st) != 0) {
        printf("Error: /etc/vault/key.pem not found.\n");
        return 1;
    }
    if ((st.st_mode & 0777) != 0400) {
        printf("Error: /etc/vault/key.pem must have 0400 permissions.\n");
        return 1;
    }

    FILE *f_cert = fopen("/etc/vault/cert.pem", "r");
    if (!f_cert) {
        printf("Error: /etc/vault/cert.pem not found.\n");
        return 1;
    }

    char cert_data[8192];
    size_t n = fread(cert_data, 1, sizeof(cert_data)-1, f_cert);
    cert_data[n] = '\0';
    fclose(f_cert);

    if (strstr(cert_data, "SyndicateAuditors") == NULL) {
        printf("Error: Certificate does not contain required Subject attributes.\n");
        return 1;
    }

    FILE *fin = fopen(argv[1], "rb");
    if (!fin) {
        printf("Error: Cannot open input file.\n");
        return 1;
    }
    FILE *fout = fopen(argv[2], "wb");
    if (!fout) {
        printf("Error: Cannot open output file.\n");
        return 1;
    }

    int c;
    while ((c = fgetc(fin)) != EOF) {
        fputc(c ^ 0x42, fout);
    }

    fclose(fin);
    fclose(fout);
    printf("Decryption successful.\n");
    return 0;
}
EOF

    # Compile and strip
    gcc /app/vault_decrypt.c -o /app/vault_decrypt
    strip /app/vault_decrypt
    rm /app/vault_decrypt.c

    # Create and encrypt dummy audio file
    python3 -c "
with open('/app/evidence.wav', 'wb') as f:
    f.write(b'RIFF$   WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00D\xac\x00\x00\x88X\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00')

with open('/app/evidence.wav', 'rb') as fin, open('/app/evidence.enc', 'wb') as fout:
    for byte in fin.read():
        fout.write(bytes([byte ^ 0x42]))
"
    rm /app/evidence.wav

    chmod -R 755 /app
    chmod 644 /app/evidence.enc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
