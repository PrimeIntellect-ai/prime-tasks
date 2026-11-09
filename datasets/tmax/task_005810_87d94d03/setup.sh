#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > experiments.csv
run_id,lr,fold,accuracy
r1,0.01,1,0.81
r2,0.01,2,0.82
r3,0.01,3,0.83
r4,0.01,4,0.84
r5,0.01,5,0.85
r6,0.01,6,0.81
r7,0.01,7,0.82
r8,0.01,8,0.83
r9,0.01,9,0.84
r10,0.01,10,0.85
r11,0.05,1,0.90
r12,0.05,2,0.92
r13,0.05,3,0.91
r14,0.05,4,0.93
r15,0.05,5,0.94
r16,0.05,6,0.89
r17,0.05,7,0.90
r18,0.05,8,0.91
r19,0.05,9,0.92
r20,0.05,10,0.95
r21,0.1,1,0.75
r22,0.1,2,0.76
r23,0.1,3,0.78
r24,0.1,4,0.72
r25,0.1,5,0.74
r26,0.1,6,0.75
r27,0.1,7,0.76
r28,0.1,8,0.77
r29,0.1,9,0.79
r30,0.1,10,0.75
EOF

    awk 'BEGIN{
        srand(12345);
        for(i=0; i<100; i++) {
            s=""; 
            for(j=0; j<10; j++) {
                s=s (int(rand()*10)+1) ","; 
            }
            sub(/,$/,"",s); 
            print s;
        }
    }' > bootstrap_indices.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
