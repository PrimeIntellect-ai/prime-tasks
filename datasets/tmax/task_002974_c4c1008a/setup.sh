#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make binutils wget
pip3 install pytest

# Create the legacy library
mkdir -p /app
cat << 'EOF' > /tmp/legacy_math.c
double compute_zeta_core(int iter, double val) {
    double res = val;
    for (int i = 0; i < iter; i++) {
        res = (res * 1.05) + (i * 0.1);
    }
    return res;
}
EOF
gcc -shared -fPIC -O2 /tmp/legacy_math.c -o /app/liblegacy_math.so
strip -s /app/liblegacy_math.so
rm /tmp/legacy_math.c

# Set up user workspace
useradd -m -s /bin/bash user || true
mkdir -p /home/user/vendor

# Download mongoose
wget -qO /home/user/vendor/mongoose.c https://raw.githubusercontent.com/cesanta/mongoose/7.8/mongoose.c
wget -qO /home/user/vendor/mongoose.h https://raw.githubusercontent.com/cesanta/mongoose/7.8/mongoose.h

# Create server skeleton
cat << 'EOF' > /home/user/server.c
#include "mongoose.h"
#include <stdio.h>
#include <stdlib.h>

// TODO: Add external function declaration for the legacy math core

static void fn(struct mg_connection *c, int ev, void *ev_data, void *fn_data) {
  if (ev == MG_EV_HTTP_MSG) {
    struct mg_http_message *hm = (struct mg_http_message *) ev_data;
    if (mg_http_match_uri(hm, "/zeta")) {
      // TODO: Parse 'iter' and 'val' query parameters
      // TODO: Invoke the function from the legacy shared library
      // TODO: Return the result in JSON format: {"result": 123.456}

      mg_http_reply(c, 200, "", "{\"result\": 0.0}\n");
    } else {
      mg_http_reply(c, 404, "", "Not found\n");
    }
  }
}

int main(void) {
  struct mg_mgr mgr;
  mg_mgr_init(&mgr);
  mg_http_listen(&mgr, "http://127.0.0.1:9090", fn, NULL);
  for (;;) mg_mgr_poll(&mgr, 1000);
  mg_mgr_free(&mgr);
  return 0;
}
EOF

# Create broken Makefile
cat << 'EOF' > /home/user/Makefile
server: server.c
	gcc -O2 server.c vendor/mongoose.c -I vendor -o server
EOF

chmod -R 777 /home/user
