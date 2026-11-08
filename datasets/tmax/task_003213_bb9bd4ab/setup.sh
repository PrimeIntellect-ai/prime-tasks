#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/l10n

    cat << 'EOF' > /home/user/l10n/input.jsonl
{"timestamp": 1700000000, "locale": "en-US", "message": "Hello World"}
{"timestamp": 1700003600, "locale": "es-ES", "message": "Hola"}
{"timestamp": 1700014400, "locale": "ja-JP", "message": "Konnichiwa \u3042"}
{"timestamp": 1700014500, "locale": "en-US", "message": "Second message"}
EOF

    cat << 'EOF' > /home/user/l10n/parse_logs.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        char *ts_start = strstr(line, "\"timestamp\": ");
        char *loc_start = strstr(line, "\"locale\": \"");
        char *msg_start = strstr(line, "\"message\": \"");

        if (!ts_start || !loc_start || !msg_start) continue;

        long long ts = atoll(ts_start + 13);

        loc_start += 11;
        char *loc_end = strchr(loc_start, '"');
        if (!loc_end) continue;
        *loc_end = '\0';

        msg_start += 12;
        char *msg_end = strrchr(msg_start, '"');
        if (!msg_end) continue;
        *msg_end = '\0';

        // Buggy unicode processing
        char out_msg[1024];
        int j = 0;
        for (int i = 0; i < strlen(msg_start); i++) {
            if (msg_start[i] == '\\' && msg_start[i+1] == 'u') {
                // Out of bounds crash if near end of string
                i += 5;
                out_msg[j++] = '?';
            } else {
                out_msg[j++] = msg_start[i];
            }
        }
        out_msg[j] = '\0';

        printf("%lld\t%s\t%s\n", ts, loc_start, out_msg);
    }
    return 0;
}
EOF

    chmod +x /home/user/l10n/parse_logs.c
    chown -R user:user /home/user/l10n

    chmod -R 777 /home/user
