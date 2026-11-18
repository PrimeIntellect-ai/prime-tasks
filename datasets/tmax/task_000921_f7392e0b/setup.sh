#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math-ci
    cd /home/user/math-ci
    go mod init mathvm

    cat << 'EOF' > vm.h
#ifndef VM_H
#define VM_H

#define OP_PUSH 1
#define OP_ADD 2
#define OP_SUB 3

double evaluate(int* opcodes, double* values, int count);

#endif
EOF

    cat << 'EOF' > vm.c
#include "vm.h"

double evaluate(int* opcodes, double* values, int count) {
    double stack[256];
    int sp = 0;
    int val_idx = 0;

    for (int i = 0; i < count; i++) {
        switch (opcodes[i]) {
            case OP_PUSH:
                stack[sp++] = values[val_idx++];
                break;
            case OP_ADD: {
                double a = stack[--sp];
                double b = stack[--sp];
                stack[sp++] = b + a;
                break;
            }
            case OP_SUB: {
                double a = stack[--sp];
                double b = stack[--sp];
                // BUG: should be b - a
                stack[sp++] = a - b; 
                break;
            }
        }
    }
    return stack[--sp];
}
EOF

    cat << 'EOF' > Makefile
all: libmathvm.so

vm.o: vm.c
	gcc -c vm.c

libmathvm.so: vm.o
	gcc -shared vm.o libmathvm.so

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > mathvm.go
package mathvm

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L. -lmathvm
#include "vm.h"
*/
import "C"

const (
	OpPush = 1
	OpAdd  = 2
	OpSub  = 3
)

func Evaluate(opcodes []int, values []float64) float64 {
	if len(opcodes) == 0 {
		return 0
	}

	var cOpcodes []C.int
	for _, op := range opcodes {
		cOpcodes = append(cOpcodes, C.int(op))
	}

	var cValues []C.double
	for _, v := range values {
		cValues = append(cValues, C.double(v))
	}

	// handle empty values gracefully for C pointers
	if len(cValues) == 0 {
	    cValues = append(cValues, C.double(0))
	}

	result := C.evaluate((*C.int)(&cOpcodes[0]), (*C.double)(&cValues[0]), C.int(len(opcodes)))
	return float64(result)
}
EOF

    cat << 'EOF' > mathvm_test.go
package mathvm

import (
	"math/rand"
	"reflect"
	"testing"
	"testing/quick"
)

func TestMathVMAgainstGo(t *testing.T) {
	// Property: a - b should be equal in VM and Go
	f := func(a float64, b float64) bool {
		opcodes := []int{OpPush, OpPush, OpSub}
		values := []float64{a, b}

		vmResult := Evaluate(opcodes, values)
		goResult := a - b

		return vmResult == goResult
	}

	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}

	// Property: a + b should be equal in VM and Go
	fAdd := func(a float64, b float64) bool {
		opcodes := []int{OpPush, OpPush, OpAdd}
		values := []float64{a, b}

		vmResult := Evaluate(opcodes, values)
		goResult := a + b

		return vmResult == goResult
	}

	if err := quick.Check(fAdd, nil); err != nil {
		t.Error(err)
	}
}
EOF

    chmod -R 777 /home/user
