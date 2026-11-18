#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets

    # Install required packages
    apt-get install -y nginx valgrind gcc make libwebsockets-dev

    # Create directories
    mkdir -p /home/user/divn

    # Create server.c
    cat << 'EOF' > /home/user/divn/server.c
#include <libwebsockets.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint16_t compute_fletcher16(const uint8_t *data, size_t len) {
    return 0; // TODO: Implement Fletcher-16
}

static int callback_divn(struct lws *wsi, enum lws_callback_reasons reason,
                         void *user, void *in, size_t len) {
    switch (reason) {
        case LWS_CALLBACK_RECEIVE: {
            // BUG: Memory leak here
            char *leak_buf = malloc(len + 1);
            memcpy(leak_buf, in, len);
            leak_buf[len] = '\0';

            uint16_t checksum = compute_fletcher16((const uint8_t *)in, len);

            char response[64];
            int response_len = snprintf(response, sizeof(response), "%u", checksum);

            unsigned char buf[LWS_PRE + 64];
            memcpy(&buf[LWS_PRE], response, response_len);

            lws_write(wsi, &buf[LWS_PRE], response_len, LWS_WRITE_TEXT);
            break;
        }
        default:
            break;
    }
    return 0;
}

static struct lws_protocols protocols[] = {
    {
        "divn-protocol",
        callback_divn,
        0,
        1024,
    },
    { NULL, NULL, 0, 0 } /* terminator */
};

int main(void) {
    struct lws_context_creation_info info;
    struct lws_context *context;

    memset(&info, 0, sizeof(info));
    info.port = 9000;
    info.protocols = protocols;

    context = lws_create_context(&info);
    if (!context) {
        fprintf(stderr, "lws init failed\n");
        return -1;
    }

    while (1) {
        lws_service(context, 1000);
    }

    lws_context_destroy(context);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/divn/Makefile
divn_server: server.c
	gcc -o divn_server server.c -lwebsockets
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
