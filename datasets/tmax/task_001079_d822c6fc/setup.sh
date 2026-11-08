#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libcjson-dev binutils
    pip3 install pytest scikit-learn numpy pandas

    mkdir -p /app
    cat << 'EOF' > /app/legacy_score.c
#include <stdio.h>
#include <stdlib.h>
#include <cjson/cJSON.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("SCHEMA_ERROR\n");
        return 1;
    }
    cJSON *json = cJSON_Parse(argv[1]);
    if (json == NULL) {
        printf("SCHEMA_ERROR\n");
        return 1;
    }
    cJSON *f1 = cJSON_GetObjectItemCaseSensitive(json, "f1");
    cJSON *f2 = cJSON_GetObjectItemCaseSensitive(json, "f2");
    cJSON *f3 = cJSON_GetObjectItemCaseSensitive(json, "f3");
    cJSON *f4 = cJSON_GetObjectItemCaseSensitive(json, "f4");

    if (!cJSON_IsNumber(f1) || !cJSON_IsNumber(f2) || !cJSON_IsNumber(f3) || !cJSON_IsNumber(f4)) {
        printf("SCHEMA_ERROR\n");
        cJSON_Delete(json);
        return 1;
    }

    double score = 10.5 + 3.2 * f1->valuedouble - 1.8 * f2->valuedouble + 0.5 * (f3->valuedouble * f3->valuedouble) + 2.1 * (f1->valuedouble * f4->valuedouble);
    printf("%.4f\n", score);
    cJSON_Delete(json);
    return 0;
}
EOF

    gcc -O2 /app/legacy_score.c -o /app/legacy_score -lcjson
    strip -s /app/legacy_score
    rm /app/legacy_score.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
