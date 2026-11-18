#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/evidence/http
mkdir -p /home/user/evidence/ssh
mkdir -p /home/user/evidence/bin
mkdir -p /home/user/evidence/src

cat << 'EOF' > /home/user/evidence/http/requests.log
10.0.0.52 - GET /api/data HTTP/1.1
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiam9obiJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
10.0.0.88 - GET /api/admin HTTP/1.1
Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ.
10.0.0.105 - POST /login HTTP/1.1
EOF

cat << 'EOF' > /home/user/evidence/src/auth.js
const express = require('express');
const db = require('./database');

function authenticate(req, res) {
    let username = req.body.username;
    let password = req.body.password;

    // Check credentials
    let query = "SELECT * FROM users WHERE username = '" + username + "' AND password = '" + password + "'";
    db.execute(query, (err, results) => {
        if (err) throw err;
        if (results.length > 0) {
            res.send("Success");
        } else {
            res.send("Fail");
        }
    });
}
module.exports = authenticate;
EOF

cat << 'EOF' > /home/user/evidence/ssh/sshd_config
# This is the sshd server system-wide configuration file.
Port 22
ListenAddress 0.0.0.0
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
PasswordAuthentication yes
ChallengeResponseAuthentication no
GSSAPIAuthentication yes
GSSAPICleanupCredentials no
UsePAM yes
AcceptEnv LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv LC_IDENTIFICATION LC_ALL LANGUAGE
AcceptEnv XMODIFIERS
Subsystem sftp  /usr/libexec/openssh/sftp-server
PermitRootLogin yes
EOF

# Use python to write binary files to avoid bash/Apptainer escape sequence issues
python3 -c '
import os
base = "/home/user/evidence/bin"
elf_header = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"

with open(os.path.join(base, "ls"), "wb") as f:
    f.write(elf_header)

with open(os.path.join(base, "cat"), "wb") as f:
    f.write(elf_header)

with open(os.path.join(base, "systemd-resolve"), "wb") as f:
    f.write(elf_header + b"\nc2.evil-hacker-empire.xyz\n")
'

cd /home/user/evidence/bin
md5sum ls > checksums.md5
md5sum cat >> checksums.md5
echo "d41d8cd98f00b204e9800998ecf8427e  systemd-resolve" >> checksums.md5

chmod -R 777 /home/user
