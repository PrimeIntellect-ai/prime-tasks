#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make pkg-config libwebsockets-dev libjansson-dev
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_broker
    cd /home/user/telemetry_broker

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -Wextra -g
LDFLAGS = 

# TODO: Add pkg-config flags for libwebsockets and jansson
# CFLAGS += ...
# LDFLAGS += ...

telemetry_broker: server.c
	$(CC) $(CFLAGS) server.c -o telemetry_broker $(LDFLAGS)

clean:
	rm -f telemetry_broker
EOF

    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <libwebsockets.h>
#include <jansson.h>

struct per_session_data {
    // Add your rate limiting state here
    long long message_timestamps[10];
    int msg_count;
};

// Return current time in milliseconds
long long get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)(tv.tv_sec) * 1000 + (tv.tv_usec) / 1000;
}

// TODO: Implement expression parser and evaluator
// Returns 1 if JSON matches expression, 0 otherwise
int evaluate_filter(json_t *root, const char *expr) {
    // Your implementation here
    return 0;
}

// TODO: Implement rate limit (Max 3 messages per 1000ms)
// Returns 1 if allowed, 0 if dropped
int check_rate_limit(struct per_session_data *pss) {
    // Your implementation here
    return 1;
}

static int callback_broker(struct lws *wsi, enum lws_callback_reasons reason,
                           void *user, void *in, size_t len) {
    struct per_session_data *pss = (struct per_session_data *)user;
    const char *filter_expr = (const char *)lws_context_user(lws_get_context(wsi));

    switch (reason) {
        case LWS_CALLBACK_ESTABLISHED:
            memset(pss, 0, sizeof(struct per_session_data));
            break;

        case LWS_CALLBACK_RECEIVE: {
            if (!check_rate_limit(pss)) {
                lws_write(wsi, (unsigned char *)"RATE_LIMITED", 12, LWS_WRITE_TEXT);
                break;
            }

            char *msg = malloc(len + 1);
            memcpy(msg, in, len);
            msg[len] = '\0';

            json_error_t error;
            json_t *root = json_loads(msg, 0, &error);
            if (!root) {
                free(msg);
                lws_write(wsi, (unsigned char *)"INVALID_JSON", 12, LWS_WRITE_TEXT);
                break;
            }

            if (evaluate_filter(root, filter_expr)) {
                lws_write(wsi, (unsigned char *)"ACCEPTED", 8, LWS_WRITE_TEXT);
            } else {
                lws_write(wsi, (unsigned char *)"REJECTED", 8, LWS_WRITE_TEXT);
            }

            json_decref(root);
            free(msg);
            break;
        }
        default:
            break;
    }
    return 0;
}

static struct lws_protocols protocols[] = {
    { "broker-protocol", callback_broker, sizeof(struct per_session_data), 1024, 0, NULL, 0 },
    { NULL, NULL, 0, 0, 0, NULL, 0 }
};

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <port> <filter_expr>\n", argv[0]);
        return 1;
    }

    int port = atoi(argv[1]);
    const char *filter_expr = argv[2];

    struct lws_context_creation_info info;
    memset(&info, 0, sizeof(info));
    info.port = port;
    info.protocols = protocols;
    info.user = (void *)filter_expr;

    struct lws_context *context = lws_create_context(&info);
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

    cat << 'EOF' > test_runner.py
import asyncio
import websockets
import time
import json
import sys

async def run_test():
    try:
        async with websockets.connect("ws://localhost:8080") as ws:
            results = []

            # Test 1-3: Filter logic
            await ws.send(json.dumps({"warnings": 2}))
            results.append(await ws.recv()) # Expected: ACCEPTED

            await ws.send(json.dumps({"warnings": 10}))
            results.append(await ws.recv()) # Expected: REJECTED

            await ws.send(json.dumps({"errors": 0}))
            results.append(await ws.recv()) # Expected: REJECTED (no warnings key)

            # Test 4-6: Rate Limiting
            # Send 4 messages quickly. Max is 3 per sec.
            for i in range(4):
                await ws.send(json.dumps({"warnings": 1}))

            rl_results = []
            for i in range(4):
                rl_results.append(await ws.recv())

            if results == ["ACCEPTED", "REJECTED", "REJECTED"] and rl_results.count("RATE_LIMITED") >= 1:
                with open("/home/user/telemetry_broker/validation.log", "w") as f:
                    f.write("SUCCESS: All tests passed.\n")
                print("All tests passed.")
            else:
                with open("/home/user/telemetry_broker/validation.log", "w") as f:
                    f.write(f"FAILED: Filter res {results}, RL res {rl_results}\n")
                print("Tests failed.")
    except Exception as e:
        with open("/home/user/telemetry_broker/validation.log", "w") as f:
            f.write(f"ERROR: {str(e)}\n")

if __name__ == "__main__":
    asyncio.run(run_test())
EOF
    chmod +x test_runner.py

    chmod -R 777 /home/user
