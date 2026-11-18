#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make jq gawk
pip3 install pytest

mkdir -p /app/string_utils-1.2.0

cat << 'EOF' > /app/string_utils-1.2.0/str_tool.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

void urlencode(const char *s) {
    // dummy use of math to force -lm
    double dummy = pow(2.0, 3.0);
    for (; *s; s++) {
        if ((*s >= '0' && *s <= '9') ||
            (*s >= 'A' && *s <= 'Z') ||
            (*s >= 'a' && *s <= 'z') ||
            *s == '-' || *s == '_' || *s == '.' || *s == '~') {
            putchar(*s);
        } else {
            printf("%%%02X", (unsigned char)*s);
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    if (strcmp(argv[1], "encode") == 0) {
        urlencode(argv[2]);
    }
    return 0;
}
EOF

cat << 'EOF' > /app/string_utils-1.2.0/Makefile
CC=clang

all: str_tool

str_tool.o: str_tool.c
	$(CC) -c str_tool.c

str_tool: str_tool.o
	$(CC) -o str_tool str_tool.o
EOF

cat << 'EOF' > /app/reference_oracle.sh
#!/bin/bash
input="$1"
declare -A vars
IFS='|' read -ra cmds <<< "$input"
for cmd_raw in "${cmds[@]}"; do
    cmd=$(echo "$cmd_raw" | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [[ -z "$cmd" ]]; then continue; fi
    read -r op args <<< "$cmd"
    if [[ "$op" == "SET" ]]; then
        read -r var val <<< "$args"
        vars["$var"]="$val"
    elif [[ "$op" == "APPEND" ]]; then
        read -r var val <<< "$args"
        if [[ -z "${vars[$var]+x}" ]]; then
            vars["$var"]="$val"
        else
            vars["$var"]="${vars[$var]},$val"
        fi
    elif [[ "$op" == "SORT" ]]; then
        read -r var <<< "$args"
        if [[ -n "${vars[$var]+x}" ]]; then
            sorted=$(echo "${vars[$var]}" | tr ',' '\n' | sort | paste -sd, -)
            vars["$var"]="$sorted"
        fi
    elif [[ "$op" == "MERGE" ]]; then
        read -r var1 var2 <<< "$args"
        combined="${vars[$var1]},${vars[$var2]}"
        merged=$(echo "$combined" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, -)
        vars["$var1"]="$merged"
    elif [[ "$op" == "URLENCODE" ]]; then
        read -r var <<< "$args"
        if [[ -n "${vars[$var]+x}" ]]; then
            encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='~.-_'))" "${vars[$var]}")
            vars["$var"]="$encoded"
        fi
    elif [[ "$op" == "JSON" ]]; then
        json="{}"
        for k in $(printf '%s\n' "${!vars[@]}" | sort); do
            if [[ -n "$k" ]]; then
                json=$(echo "$json" | jq -c --arg k "$k" --arg v "${vars[$k]}" '.[$k] = $v')
            fi
        done
        # Pretty print at the end
        echo "$json" | jq .
        exit 0
    fi
done
EOF
chmod +x /app/reference_oracle.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
