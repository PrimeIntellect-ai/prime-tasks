#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y ffmpeg bubblewrap golang-go openssl wget

    mkdir -p /app/certs

    # Generate X.509 certificate chain
    cd /app/certs

    # Root CA
    openssl genrsa -out root.key 2048
    openssl req -x509 -new -nodes -key root.key -sha256 -days 1024 -out root.pem -subj "/C=US/ST=State/L=City/O=Org/CN=RootCA"

    # Intermediate CA
    openssl genrsa -out intermediate.key 2048
    openssl req -new -key intermediate.key -out intermediate.csr -subj "/C=US/ST=State/L=City/O=Org/CN=IntermediateCA"

    # Create extension config for intermediate
    cat > v3_intermediate.ext <<EOF
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

    openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial -out intermediate.pem -days 500 -sha256 -extfile v3_intermediate.ext

    # Server Cert
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/C=US/ST=State/L=City/O=Org/CN=Server"
    openssl x509 -req -in server.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out server.pem -days 500 -sha256

    cd /

    # Generate the audio file using python
    pip3 install gTTS
    python3 -c "
from gtts import gTTS
text = 'The backup server is at 10.5.22.115 and the billing account uses the card 4111-1111-1111-1111 for processing.'
tts = gTTS(text)
tts.save('/app/voip_intercept.mp3')
"
    ffmpeg -i /app/voip_intercept.mp3 -ar 16000 -ac 1 -c:a pcm_s16le /app/voip_intercept.wav
    rm /app/voip_intercept.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
