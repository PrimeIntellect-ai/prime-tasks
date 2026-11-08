#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/libcurvefit-1.0

    cat << 'EOF' > /app/libcurvefit-1.0/curvefit.h
#ifndef CURVEFIT_H
#define CURVEFIT_H
int fit_melting_curve(const float* absorbances, int n_points, float* tm);
#endif
EOF

    cat << 'EOF' > /app/libcurvefit-1.0/curvefit.c
#include "curvefit.h"
#include <math.h>

// A dummy implementation of finding the inflection point for testing
int fit_melting_curve(const float* absorbances, int n_points, float* tm) {
    float max_diff = 0.0;
    int max_idx = 0;
    for(int i=1; i<n_points; i++) {
        float diff = absorbances[i] - absorbances[i-1];
        if (diff > max_diff) {
            max_diff = diff;
            max_idx = i;
        }
    }
    // Simulate usage of math library so -lm is actually needed
    float dummy = exp(1.0); 
    *tm = 20.0f + max_idx - 0.5f + (dummy*0.0);
    return 0;
}
EOF

    cat << 'EOF' > /app/libcurvefit-1.0/Makefile
CC=gcc
CFLAGS=-fPIC -O2 -Wall

all: libcurvefit.so

curvefit.o: curvefit.c
	$(CC) $(CFLAGS) -c curvefit.c

libcurvefit.so: curvefit.o
	$(CC) -shared -o libcurvefit.so curvefit.o

clean:
	rm -f *.o *.so
EOF

    # Ensure actual tabs are used in the Makefile
    sed -i 's/^    /\t/g' /app/libcurvefit-1.0/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
