#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/syslog.log
Jan 10 09:12:01 server sshd[101]: Failed password for alice from 10.0.0.2 port 33412 ssh2
Jan 10 09:14:00 server sshd[102]: Accepted password for alice from 10.0.0.2 port 33413 ssh2
Jan 10 10:01:12 server sshd[105]: Failed password for bob from 192.168.1.50 port 44211 ssh2
Jan 10 10:01:15 server sshd[105]: Failed password for bob from 192.168.1.50 port 44212 ssh2
Jan 10 10:01:18 server sshd[105]: Failed password for bob from 192.168.1.50 port 44213 ssh2
Jan 10 10:01:21 server sshd[105]: Failed password for bob from 192.168.1.50 port 44214 ssh2
Jan 10 10:01:30 server sshd[106]: Accepted password for bob from 192.168.1.50 port 44215 ssh2
Jan 10 11:22:01 server sshd[110]: Failed password for charlie from 172.16.0.5 port 11223 ssh2
Jan 10 11:22:05 server sshd[110]: Failed password for charlie from 172.16.0.5 port 11224 ssh2
Jan 10 11:22:09 server sshd[110]: Failed password for charlie from 172.16.0.5 port 11225 ssh2
Jan 10 11:22:15 server sshd[111]: Accepted password for charlie from 172.16.0.5 port 11226 ssh2
Jan 10 12:00:00 server sshd[115]: Failed password for david from 10.0.0.99 port 55432 ssh2
Jan 10 12:00:05 server sshd[115]: Failed password for david from 10.0.0.99 port 55433 ssh2
Jan 10 12:00:10 server sshd[115]: Failed password for david from 10.0.0.99 port 55434 ssh2
EOF

    cat << 'EOF' > /home/user/audit_data/shadow.bak
root:1175ebba207ab7aa19280d5b7a1e0b52
alice:5ebe2294ecd0e0f08eab7690d2a6ee69
bob:d8578edf8458ce06fbc5bb76a58c5ca4
charlie:b5dfbdcc9cd602dcbc66ed62baeb3bfd
david:098f6bcd4621d373cade4e832627b4f6
EOF

    cat << 'EOF' > /home/user/audit_data/wordlist.txt
admin
password
secret
qwerty
123456
letmein1
sunshine
dragon
EOF

    cat << 'EOF' > /home/user/audit_data/passwd.bak
root:x:0:0:root:/root:/bin/bash
alice:x:1001:1001:Alice:/home/alice:/bin/bash
bob:x:1002:1002:Bob:/home/bob:/bin/bash
charlie:x:1003:1003:Charlie:/home/charlie:/bin/bash
david:x:1004:1004:David:/home/david:/bin/bash
EOF

    cat << 'EOF' > /home/user/audit_data/netstat.txt
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       User       Inode      PID/Program name    
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      0          12345      -                   
tcp        0      0 0.0.0.0:4444            0.0.0.0:*               LISTEN      1002       12346      -                   
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      1003       12347      -                   
tcp        0      0 127.0.0.1:3306          0.0.0.0:*               LISTEN      105        12348      -                   
EOF

    chmod -R 777 /home/user
