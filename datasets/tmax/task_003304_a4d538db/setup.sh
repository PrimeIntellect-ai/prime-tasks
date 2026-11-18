#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/rpn_calc

    cat << 'EOF' > /home/user/rpn_calc/stack.h
#ifndef STACK_H
#define STACK_H
void push(int val);
int pop(void);
#endif
EOF

    cat << 'EOF' > /home/user/rpn_calc/stack.c
#include "stack.h"
#include <stdio.h>
#include <stdlib.h>

#define MAX 100
static int stack[MAX];
static int top = -1;

void push(int val) {
    if (top < MAX - 1) {
        stack[++top] = val;
    }
}

int pop(void) {
    if (top >= 0) {
        return stack[top--];
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/rpn_calc/main.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "stack.h"

int main() {
    char token[32];
    while (scanf("%s", token) != EOF) {
        if (strcmp(token, "+") == 0) {
            push(pop() + pop());
        } else if (strcmp(token, "P") == 0) {
            printf("%d\n", pop());
        } else {
            push(atoi(token));
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/rpn_calc/Makefile
CC=gcc
CFLAGS=-Wall

calc: main.o stack.o
	$(CC) $(CFLAGS) -o calc main.o stack.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

stack.o: stack.c
	$(CC) $(CFLAGS) -c stack.c

clean:
	rm -f *.o calc
EOF

    cat << 'EOF' > /home/user/rpn_calc/feature-factorial.patch
--- main.c
+++ main.c
@@ -3,6 +3,8 @@
 #include <stdlib.h>
 #include "stack.h"

+int factorial(int n);
+
 int main() {
     char token[32];
     while (scanf("%s", token) != EOF) {
@@ -10,6 +12,8 @@
             push(pop() + pop());
+        } else if (strcmp(token, "!") == 0) {
+            push(factorial(pop()));
         } else if (strcmp(token, "P") == 0) {
             printf("%d\n", pop());
         } else {
--- Makefile
+++ Makefile
@@ -1,8 +1,11 @@
 CC=gcc
 CFLAGS=-Wall

-calc: main.o stack.o
+calc: main.o stack.o math_ops.o
 	$(CC) $(CFLAGS) -o calc main.o stack.o

 main.o: main.c
 	$(CC) $(CFLAGS) -c main.c

 stack.o: stack.c
 	$(CC) $(CFLAGS) -c stack.c
+
+math_ops.o: math_ops.c
+	$(CC) $(CFLAGS) -c math_ops.c
--- /dev/null
+++ math_ops.c
@@ -0,0 +1,8 @@
+int factorial(int n) {
+    int res = 1;
+    for (int i = 1; i < n; i++) {
+        res *= i;
+    }
+    return res;
+}
EOF

    chown -R user:user /home/user/rpn_calc
    chmod -R 777 /home/user
