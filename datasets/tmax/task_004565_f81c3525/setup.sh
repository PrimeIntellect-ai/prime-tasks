#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /app
# Generate the screenshot image
convert -size 800x100 xc:black -font DejaVu-Sans-Mono -pointsize 18 -fill white -annotate +10+50 "user@host:~$ ./start_service.sh --password c3VwM3Jfc2VjcmV0XzEzMzc=" /app/arch_screenshot.png

# Create training corpus directories
mkdir -p /home/user/corpus/evil
mkdir -p /home/user/corpus/clean

# Create evaluation corpus directories (hidden from agent but used by verifier)
mkdir -p /app/eval_corpus/evil
mkdir -p /app/eval_corpus/clean

# Populate training evil corpus
echo "<script>alert(1)</script>" > /home/user/corpus/evil/payload1.txt
echo "admin' --" > /home/user/corpus/evil/payload2.txt
echo "newpass; cat /etc/passwd" > /home/user/corpus/evil/payload3.txt

# Populate training clean corpus
echo '{"password": "newpassword123"}' > /home/user/corpus/clean/payload1.txt
echo '{"password": "securePass!@#"}' > /home/user/corpus/clean/payload2.txt

# Populate evaluation evil corpus
echo "<img src=x onerror=alert(1)>" > /app/eval_corpus/evil/eval1.txt
echo "1' OR '1'='1" > /app/eval_corpus/evil/eval2.txt
echo "password; rm -rf /" > /app/eval_corpus/evil/eval3.txt
echo "javascript:alert(document.cookie)" > /app/eval_corpus/evil/eval4.txt
echo "admin' OR 1=1#" > /app/eval_corpus/evil/eval5.txt
echo "1; ls -la" > /app/eval_corpus/evil/eval6.txt

# Populate evaluation clean corpus
echo '{"password": "anotherpassword321"}' > /app/eval_corpus/clean/eval1.txt
echo '{"password": "MySuperSecretPassword99"}' > /app/eval_corpus/clean/eval2.txt
echo '{"password": "JustANormalPassword"}' > /app/eval_corpus/clean/eval3.txt
echo '{"password": "password123456"}' > /app/eval_corpus/clean/eval4.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
