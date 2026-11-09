#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc cargo
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create SQLite database and schema
    sqlite3 /app/astro_data.db <<EOF
CREATE TABLE stars (id INTEGER PRIMARY KEY, mass REAL, name TEXT);
CREATE TABLE observations (id INTEGER PRIMARY KEY, star_id INTEGER, brightness REAL);
CREATE INDEX idx_obs_star ON observations(star_id);
CREATE INDEX idx_stars_mass ON stars(mass);
EOF

    # Create the C program for the compiler
    cat << 'EOF' > /tmp/compiler.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char buf[1024];
    size_t n = fread(buf, 1, 1023, f);
    buf[n] = 0;
    fclose(f);

    if (strstr(buf, "GET STARS")) printf("SELECT * FROM stars ");
    if (strstr(buf, "JOIN OBS")) printf("JOIN observations ON observations.star_id = stars.id ");
    if (strstr(buf, "FILTER mass > 10")) printf("WHERE mass > 10 ");
    if (strstr(buf, "MAX 500")) printf("LIMIT 500;\n");
    else if (strstr(buf, "MAX 50")) printf("LIMIT 50;\n");
    else printf(";\n");

    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O3 -s /tmp/compiler.c -o /app/astro_dsl_compiler
    chmod +x /app/astro_dsl_compiler
    rm /tmp/compiler.c

    # Create corpus files
    echo "GET STARS FILTER mass > 10 MAX 50" > /app/corpus/clean/query1.astro
    echo "GET STARS MAX 50" > /app/corpus/evil/query1.astro
    echo "GET STARS FILTER mass > 10 MAX 500" > /app/corpus/evil/query2.astro

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
