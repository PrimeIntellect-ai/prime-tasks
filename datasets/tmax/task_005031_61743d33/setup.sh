#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sys_audit

    cat << 'EOF' > /home/user/sys_audit/etc_passwd
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
sysadmin:x:0:0:sysadmin:/home/sysadmin:/bin/bash
user:x:1000:1000:user:/home/user:/bin/bash
guest:x:1001:1001:guest:/home/guest:/bin/bash
hiddenshell:x:0:0:hiddenshell:/tmp:/bin/sh
EOF

    cat << 'EOF' > /home/user/sys_audit/postfix_main.cf
smtpd_banner = $myhostname ESMTP $mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
mynetworks = 127.0.0.0/8, 0.0.0.0/0
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
alias_maps = hash:/etc/aliases
EOF

    cat << 'EOF' > /home/user/sys_audit/iptables_save.txt
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 25 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 4444 -j ACCEPT
-A INPUT -p udp -m udp --dport 53 -j ACCEPT
COMMIT
EOF

    cat << 'EOF' > /home/user/sys_audit/ping_results.txt
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms

PING 10.9.8.7 (10.9.8.7) 56(84) bytes of data.
--- 10.9.8.7 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2054ms

PING 192.168.1.100 (192.168.1.100) 56(84) bytes of data.
--- 192.168.1.100 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2001ms

PING 172.16.0.5 (172.16.0.5) 56(84) bytes of data.
--- 172.16.0.5 ping statistics ---
3 packets transmitted, 1 received, 66% packet loss, time 2010ms
EOF

    chown -R user:user /home/user/sys_audit
    chmod -R 777 /home/user
