#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx socat gcc
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/merger.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse_and_merge(char *line1, char *line2) {
    int arr1[1000], arr2[1000], out[2000];
    int n1 = 0, n2 = 0;

    char *token = strtok(line1, " \n");
    while (token != NULL) {
        arr1[n1++] = atoi(token);
        token = strtok(NULL, " \n");
    }

    token = strtok(line2, " \n");
    while (token != NULL) {
        arr2[n2++] = atoi(token);
        token = strtok(NULL, " \n");
    }

    int i = 0, j = 0, k = 0;
    while (i < n1 && j < n2) {
        if (arr1[i] < arr2[j]) {
            out[k++] = arr1[i++];
        } else if (arr1[i] > arr2[j]) {
            out[k++] = arr2[j++];
        } else {
            out[k++] = arr1[i++];
            j++; // Bug: Drops duplicate elements
        }
    }
    while (i < n1) out[k++] = arr1[i++];
    while (j < n2) out[k++] = arr2[j++];

    for (int x = 0; x < k; x++) {
        printf("%d%s", out[x], (x == k - 1) ? "" : " ");
    }
    printf("\n");
    fflush(stdout);
}

int main() {
    char line1[8192], line2[8192];
    if (!fgets(line1, sizeof(line1), stdin)) return 0;
    if (!fgets(line2, sizeof(line2), stdin)) return 0;
    parse_and_merge(line1, line2);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/test_merge.py
import socket
from hypothesis import given, settings
import hypothesis.strategies as st

@settings(max_examples=100, deadline=1000)
@given(st.lists(st.integers(min_value=-1000, max_value=1000), max_size=50),
       st.lists(st.integers(min_value=-1000, max_value=1000), max_size=50))
def test_merge_service(list1, list2):
    list1.sort()
    list2.sort()

    expected = sorted(list1 + list2)

    # Connect to the Nginx reverse proxy
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(("127.0.0.1", 8080))

    msg = " ".join(map(str, list1)) + "\n" + " ".join(map(str, list2)) + "\n"
    s.sendall(msg.encode('utf-8'))

    data = s.recv(8192).decode('utf-8').strip()
    s.close()

    if not expected:
        assert data == ""
    else:
        actual = list(map(int, data.split()))
        assert actual == expected, f"Expected {expected}, got {actual}"
EOF

    chmod -R 777 /home/user
