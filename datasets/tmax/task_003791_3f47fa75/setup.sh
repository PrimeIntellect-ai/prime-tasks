#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        wget \
        tar \
        libelf-dev \
        pkg-config \
        gperf \
        libseccomp-dev

    pip3 install pytest

    mkdir -p /app/vendored /app/libs /opt/oracle

    cd /app/vendored
    wget https://github.com/seccomp/libseccomp/releases/download/v2.5.4/libseccomp-2.5.4.tar.gz
    tar -xzf libseccomp-2.5.4.tar.gz
    rm libseccomp-2.5.4.tar.gz

    # Apply perturbation
    sed -i 's/CFLAGS="-g -O2"/CFLAGS="-O2 -mwrong-arch"/g' /app/vendored/libseccomp-2.5.4/configure

    # Build oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <seccomp.h>
#include <libelf.h>
#include <gelf.h>

std::vector<uint8_t> b64_decode(const std::string& in) {
    std::vector<uint8_t> out;
    std::vector<int> T(256, -1);
    for (int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i;
    int val = 0, valb = -8;
    for (uint8_t c : in) {
        if (T[c] == -1) break;
        val = (val << 6) + T[c];
        valb += 6;
        if (valb >= 0) {
            out.push_back(char((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    return out;
}

int main(int argc, char** argv) {
    if (argc != 3) return 255;
    if (elf_version(EV_CURRENT) == EV_NONE) return 255;
    int fd = open(argv[1], O_RDONLY, 0);
    if (fd < 0) return 255;
    Elf* elf = elf_begin(fd, ELF_C_READ, NULL);
    if (!elf) return 255;
    size_t shstrndx;
    if (elf_getshdrstrndx(elf, &shstrndx) != 0) return 255;
    Elf_Scn* scn = NULL;
    std::string payload;
    bool found = false;
    while ((scn = elf_nextscn(elf, scn)) != NULL) {
        GElf_Shdr shdr;
        if (gelf_getshdr(scn, &shdr) != &shdr) continue;
        const char* name = elf_strptr(elf, shstrndx, shdr.sh_name);
        if (name && strcmp(name, ".secpolicy") == 0) {
            Elf_Data* data = elf_getdata(scn, NULL);
            if (data && data->d_buf) {
                payload.assign((const char*)data->d_buf, data->d_size);
                found = true;
            }
            break;
        }
    }
    elf_end(elf);
    close(fd);
    if (!found) return 255;

    auto decoded = b64_decode(payload);
    std::string decrypted;
    for (auto c : decoded) decrypted += (char)(c ^ 0x5A);

    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL);
    if (!ctx) return 255;
    std::stringstream ss(decrypted);
    std::string sys;
    while (std::getline(ss, sys, ',')) {
        int sys_num = seccomp_syscall_resolve_name(sys.c_str());
        if (sys_num != __NR_SCMP_ERROR) seccomp_rule_add(ctx, SCMP_ACT_ALLOW, sys_num, 0);
    }
    if (seccomp_load(ctx) < 0) return 255;
    seccomp_release(ctx);

    char* exec_args[] = { argv[1], argv[2], NULL };
    char* exec_env[] = { NULL };
    execve(argv[1], exec_args, exec_env);
    return 255;
}
EOF

    g++ -O2 /opt/oracle/oracle.cpp -o /opt/oracle/secure_runner_oracle -lelf -lseccomp
    rm /opt/oracle/oracle.cpp
    chmod 700 /opt/oracle
    chmod 755 /opt/oracle/secure_runner_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
