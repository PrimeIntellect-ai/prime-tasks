#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl
    pip3 install pytest

    mkdir -p /home/user/pipeline
    mkdir -p /app

    # Create dummy wav file
    python3 -c "import wave, struct; w = wave.open('/app/voicemail.wav', 'w'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframesraw(struct.pack('<h', 0)*16000); w.close()"

    # Create mock transcription tool
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
if [[ "$*" == *"/app/voicemail.wav"* ]]; then
    echo "System update required for nodes alpha and beta."
else
    echo "Error processing audio."
fi
EOF
    chmod +x /usr/local/bin/whisper

    # Create Makefile with missing object file in link target
    cat << 'EOF' > /home/user/pipeline/Makefile
CC=gcc
CFLAGS=-Wall

all: server test_suite

server: server.o utils.o
	$(CC) $(CFLAGS) -o server server.o

server.o: server.c
	$(CC) $(CFLAGS) -c server.c

utils.o: utils.c
	$(CC) $(CFLAGS) -c utils.c

test_suite: test.o telemetry_mock.o
	$(CC) $(CFLAGS) -o test_suite test.o telemetry_mock.o

test.o: test.c
	$(CC) $(CFLAGS) -c test.c
EOF

    # Create utils.c
    cat << 'EOF' > /home/user/pipeline/utils.c
void do_nothing() {}
EOF

    # Create server.c with intentional bug
    cat << 'EOF' > /home/user/pipeline/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd;
    struct sockaddr_in address;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    // Intentional bug: wrong port
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080); // Should be 9090

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        int new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (new_socket < 0) continue;
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        char *hello = "HTTP/1.1 200 OK\r\n\r\nOK";
        write(new_socket, hello, strlen(hello));
        close(new_socket);
    }
    return 0;
}
EOF

    # Create test.c
    cat << 'EOF' > /home/user/pipeline/test.c
#include <stdio.h>
extern int send_telemetry(const char* event);

int main() {
    if(send_telemetry("test_event") == 0) {
        printf("Test passed\n");
        return 0;
    }
    return 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
