#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make
    pip3 install pytest

    mkdir -p /app/bin

    # Create the legacy evaluator C code
    cat << 'EOF' > /app/bin/legacy_evaluator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *custom_b64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";

int decode_char(char c) {
    for (int i = 0; i < 64; i++) {
        if (custom_b64[i] == c) return i;
    }
    return -1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("ERROR\n");
        return 1;
    }
    char *input = argv[1];
    int len = strlen(input);
    if (len % 4 != 0) {
        printf("ERROR\n");
        return 1;
    }
    int out_len = len / 4 * 3;
    char *decoded = malloc(out_len + 1);
    if (!decoded) return 1;
    int j = 0;
    for (int i = 0; i < len; i += 4) {
        int n[4];
        for (int k = 0; k < 4; k++) {
            if (input[i+k] == '=') {
                n[k] = 0;
            } else {
                n[k] = decode_char(input[i+k]);
                if (n[k] == -1) {
                    printf("ERROR\n");
                    free(decoded);
                    return 1;
                }
            }
        }
        decoded[j++] = (n[0] << 2) | (n[1] >> 4);
        decoded[j++] = ((n[1] & 15) << 4) | (n[2] >> 2);
        decoded[j++] = ((n[2] & 3) << 6) | n[3];
    }
    decoded[j] = '\0';

    int stack[1024];
    int sp = 0;
    char *token = strtok(decoded, " ");
    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            if (sp < 2) { printf("ERROR\n"); free(decoded); return 1; }
            stack[sp-2] = stack[sp-2] + stack[sp-1];
            sp--;
        } else if (strcmp(token, "-") == 0) {
            if (sp < 2) { printf("ERROR\n"); free(decoded); return 1; }
            stack[sp-2] = stack[sp-2] - stack[sp-1];
            sp--;
        } else if (strcmp(token, "*") == 0) {
            if (sp < 2) { printf("ERROR\n"); free(decoded); return 1; }
            stack[sp-2] = stack[sp-2] * stack[sp-1];
            sp--;
        } else if (strcmp(token, "/") == 0) {
            if (sp < 2 || stack[sp-1] == 0) { printf("ERROR\n"); free(decoded); return 1; }
            stack[sp-2] = stack[sp-2] / stack[sp-1];
            sp--;
        } else {
            char *endptr;
            int val = strtol(token, &endptr, 10);
            if (*endptr != '\0') { printf("ERROR\n"); free(decoded); return 1; }
            stack[sp++] = val;
        }
        token = strtok(NULL, " ");
    }
    if (sp != 1) { printf("ERROR\n"); free(decoded); return 1; }
    printf("%d\n", stack[0]);
    free(decoded);
    return 0;
}
EOF

    gcc -O2 /app/bin/legacy_evaluator.c -o /app/bin/legacy_evaluator
    strip -s /app/bin/legacy_evaluator
    rm /app/bin/legacy_evaluator.c

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_integration/legacy_decoder/src

    # Create broken setup.py
    cat << 'EOF' > /home/user/api_integration/legacy_decoder/setup.py
from setuptools import setup
# deliberate syntax error and missing Extension import
setup(
    name='legacy_decoder',
    version='1.0',
    ext_modules=[Extension('legacy_decoder', ['src/decoder.c'])]
EOF

    # Create buggy C extension
    cat << 'EOF' > /home/user/api_integration/legacy_decoder/src/decoder.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

const char *std_b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int decode_char(char c) {
    for (int i = 0; i < 64; i++) {
        if (std_b64[i] == c) return i;
    }
    return -1;
}

static PyObject* decode_and_eval(PyObject* self, PyObject* args) {
    const char *input;
    if (!PyArg_ParseTuple(args, "s", &input)) return NULL;
    int len = strlen(input);
    int out_len = len / 4 * 3;
    char *decoded = malloc(out_len); // missing +1 for null terminator
    int j = 0;
    for (int i = 0; i < len; i += 4) {
        int n[4];
        for (int k = 0; k < 4; k++) {
            if (input[i+k] == '=') n[k] = 0;
            else n[k] = decode_char(input[i+k]);
        }
        decoded[j++] = (n[0] << 2) | (n[1] >> 4);
        decoded[j++] = ((n[1] & 15) << 4) | (n[2] >> 2);
        decoded[j++] = ((n[2] & 3) << 6) | n[3];
    }

    int stack[1024];
    int sp = 0;
    char *token = strtok(decoded, " ");
    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            stack[sp-2] = stack[sp-2] + stack[sp-1]; // missing bounds check
            sp--;
        } else if (strcmp(token, "-") == 0) {
            stack[sp-2] = stack[sp-2] - stack[sp-1];
            sp--;
        } else if (strcmp(token, "*") == 0) {
            stack[sp-2] = stack[sp-2] * stack[sp-1];
            sp--;
        } else if (strcmp(token, "/") == 0) {
            stack[sp-2] = stack[sp-2] / stack[sp-1];
            sp--;
        } else {
            stack[sp++] = atoi(token);
        }
        token = strtok(NULL, " ");
    }
    free(decoded);
    return PyLong_FromLong(stack[0]);
}

static PyMethodDef DecoderMethods[] = {
    {"evaluate", decode_and_eval, METH_VARARGS, "Evaluate RPN"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef decodermodule = {
    PyModuleDef_HEAD_INIT,
    "legacy_decoder",
    NULL,
    -1,
    DecoderMethods
};

PyMODINIT_FUNC PyInit_legacy_decoder(void) {
    return PyModule_Create(&decodermodule);
}
EOF

    chmod -R 777 /home/user
