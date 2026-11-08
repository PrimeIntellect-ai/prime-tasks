#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx gcc libmicrohttpd-dev
pip3 install pytest flask

mkdir -p /app
mkdir -p /opt/oracle

# Nginx config with deliberate errors
cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/v1/eval/legacy {
            proxy_pass http://127.0.0.1:5001; # Wrong port
        }
        location /api/v1/eval/fast {
            proxy_pass http://127.0.0.1:80; # Wrong port
        }
    }
}
EOF

# Legacy Python service
cat << 'EOF' > /app/legacy_service.py
from flask import Flask, request
import urllib.parse

app = Flask(__name__)

def cmp_ver(a, b):
    a_parts = [int(x) for x in a.split('.')]
    b_parts = [int(x) for x in b.split('.')]
    if a_parts < b_parts: return -1
    if a_parts > b_parts: return 1
    return 0

@app.route('/api/v1/eval/legacy')
def eval_rpn():
    expr = request.args.get('expr', '')
    tokens = expr.split()
    stack = []
    for token in tokens:
        if token == '+':
            b = int(stack.pop())
            a = int(stack.pop())
            stack.append(str(a + b))
        elif token == '-':
            b = int(stack.pop())
            a = int(stack.pop())
            stack.append(str(a - b))
        elif token == '*':
            b = int(stack.pop())
            a = int(stack.pop())
            stack.append(str(a * b))
        elif token == '/':
            b = int(stack.pop())
            a = int(stack.pop())
            stack.append(str(a // b))
        elif token == 'VER_LT':
            b = stack.pop()
            a = stack.pop()
            stack.append("1" if cmp_ver(a, b) < 0 else "0")
        elif token == 'VER_GT':
            b = stack.pop()
            a = stack.pop()
            stack.append("1" if cmp_ver(a, b) > 0 else "0")
        elif token == 'VER_EQ':
            b = stack.pop()
            a = stack.pop()
            stack.append("1" if cmp_ver(a, b) == 0 else "0")
        else:
            stack.append(token)
    return stack[0] if stack else ""

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

# C Header
cat << 'EOF' > /app/rpn_evaluator.h
#ifndef RPN_EVALUATOR_H
#define RPN_EVALUATOR_H

int evaluate_rpn(const char* expr);

#endif
EOF

# C Buggy Evaluator
cat << 'EOF' > /app/rpn_evaluator.c
#include "rpn_evaluator.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* stack[1000];
int top = 0;

// Buggy stack implementation (off-by-one)
void push(const char* val) {
    stack[++top] = strdup(val);
}

char* pop() {
    return stack[top--];
}

int evaluate_rpn(const char* expr) {
    char buf[1024];
    strncpy(buf, expr, sizeof(buf)-1);
    buf[1023] = '\0';

    char* token = strtok(buf, " ");
    top = 0; // Reset stack

    while (token) {
        if (strcmp(token, "+") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a + b);
            push(res);
        } else if (strcmp(token, "-") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a - b);
            push(res);
        } else if (strcmp(token, "*") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a * b);
            push(res);
        } else if (strcmp(token, "/") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a / b);
            push(res);
        } else if (strcmp(token, "VER_LT") == 0) {
            char* b = pop();
            char* a = pop();
            // Buggy semantic version comparison
            int cmp = strcmp(a, b);
            char res[32];
            sprintf(res, "%d", cmp < 0 ? 1 : 0);
            push(res);
        } else if (strcmp(token, "VER_GT") == 0) {
            char* b = pop();
            char* a = pop();
            // Buggy semantic version comparison
            int cmp = strcmp(a, b);
            char res[32];
            sprintf(res, "%d", cmp > 0 ? 1 : 0);
            push(res);
        } else if (strcmp(token, "VER_EQ") == 0) {
            char* b = pop();
            char* a = pop();
            // Buggy semantic version comparison
            int cmp = strcmp(a, b);
            char res[32];
            sprintf(res, "%d", cmp == 0 ? 1 : 0);
            push(res);
        } else {
            push(token);
        }
        token = strtok(NULL, " ");
    }
    return atoi(pop());
}
EOF

# CLI wrapper
cat << 'EOF' > /app/cli.c
#include "rpn_evaluator.h"
#include <stdio.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    printf("%d\n", evaluate_rpn(argv[1]));
    return 0;
}
EOF

# Fast Service Web Wrapper
cat << 'EOF' > /app/fast_service.c
#include <microhttpd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rpn_evaluator.h"

static enum MHD_Result answer_to_connection(void *cls, struct MHD_Connection *connection,
                                            const char *url, const char *method, const char *version,
                                            const char *upload_data, size_t *upload_data_size, void **con_cls) {
    const char *expr = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "expr");
    if (!expr) return MHD_NO;

    int result = evaluate_rpn(expr);
    char buf[32];
    sprintf(buf, "%d", result);

    struct MHD_Response *response = MHD_create_response_from_buffer(strlen(buf), (void*)buf, MHD_RESPMEM_MUST_COPY);
    int ret = MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);
    return ret;
}

int main() {
    struct MHD_Daemon *daemon;
    daemon = MHD_start_daemon(MHD_USE_INTERNAL_POLLING_THREAD, 5001, NULL, NULL,
                              &answer_to_connection, NULL, MHD_OPTION_END);
    if (NULL == daemon) return 1;
    getchar();
    MHD_stop_daemon(daemon);
    return 0;
}
EOF

# Create Correct Oracle Source
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* stack[1000];
int top = 0;

void push(const char* val) {
    stack[top++] = strdup(val);
}

char* pop() {
    return stack[--top];
}

int cmp_ver(const char* a, const char* b) {
    int a1=0, a2=0, a3=0;
    int b1=0, b2=0, b3=0;
    sscanf(a, "%d.%d.%d", &a1, &a2, &a3);
    sscanf(b, "%d.%d.%d", &b1, &b2, &b3);
    if (a1 != b1) return a1 - b1;
    if (a2 != b2) return a2 - b2;
    return a3 - b3;
}

int evaluate_rpn(const char* expr) {
    char buf[1024];
    strncpy(buf, expr, sizeof(buf)-1);
    buf[1023] = '\0';

    char* token = strtok(buf, " ");
    top = 0;

    while (token) {
        if (strcmp(token, "+") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a + b);
            push(res);
        } else if (strcmp(token, "-") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a - b);
            push(res);
        } else if (strcmp(token, "*") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a * b);
            push(res);
        } else if (strcmp(token, "/") == 0) {
            int b = atoi(pop());
            int a = atoi(pop());
            char res[32];
            sprintf(res, "%d", a / b);
            push(res);
        } else if (strcmp(token, "VER_LT") == 0) {
            char* b = pop();
            char* a = pop();
            int cmp = cmp_ver(a, b);
            char res[32];
            sprintf(res, "%d", cmp < 0 ? 1 : 0);
            push(res);
        } else if (strcmp(token, "VER_GT") == 0) {
            char* b = pop();
            char* a = pop();
            int cmp = cmp_ver(a, b);
            char res[32];
            sprintf(res, "%d", cmp > 0 ? 1 : 0);
            push(res);
        } else if (strcmp(token, "VER_EQ") == 0) {
            char* b = pop();
            char* a = pop();
            int cmp = cmp_ver(a, b);
            char res[32];
            sprintf(res, "%d", cmp == 0 ? 1 : 0);
            push(res);
        } else {
            push(token);
        }
        token = strtok(NULL, " ");
    }
    return atoi(pop());
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    printf("%d\n", evaluate_rpn(argv[1]));
    return 0;
}
EOF

# Compile Oracle Reference
gcc -O3 /tmp/oracle.c -o /opt/oracle/rpn_cli_reference
strip /opt/oracle/rpn_cli_reference
rm /tmp/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
