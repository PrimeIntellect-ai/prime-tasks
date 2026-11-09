#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # Generate 400 random DNA sequences
    awk 'BEGIN {
        srand(42);
        chars="ACGT";
        for(i=1; i<=400; i++) {
            seq="";
            for(j=1; j<=20; j++) {
                seq = seq substr(chars, int(rand()*4)+1, 1);
            }
            print seq;
        }
    }' > sequences.txt

    # Plant some guaranteed overlaps
    echo "ACGTACGTACGTACGTACGT" >> sequences.txt
    echo "ACGTGGGGGGGGGGGGGGGG" >> sequences.txt
    echo "TTTTTTTTTTTTTTTTACGT" >> sequences.txt

    # Step 1: Primer Extract (Fast)
    cat << 'EOF' > step1_primer_extract.sh
#!/bin/bash
# Extracts first 10 bases as primers
cut -c1-10 sequences.txt > primers.txt
EOF

    # Step 2: Alignment Filter (Fast)
    cat << 'EOF' > step2_alignment_filter.sh
#!/bin/bash
# Filters sequences containing 'CG'
grep "CG" sequences.txt > filtered_sequences.txt
EOF

    # Step 3: Graph Build (Intentionally SLOW O(N^2) bash loop)
    cat << 'EOF' > step3_graph_build.sh
#!/bin/bash
> graph_output.txt
cat filtered_sequences.txt | while read seq1; do
    cat filtered_sequences.txt | while read seq2; do
        if [ "$seq1" != "$seq2" ]; then
            suffix="${seq1: -4}"
            prefix="${seq2:0:4}"
            if [ "$suffix" == "$prefix" ]; then
                echo "$seq1 -> $seq2" >> graph_output.txt
            fi
        fi
    done
done
EOF

    # Orchestrator
    cat << 'EOF' > orchestrator.sh
#!/bin/bash
cd /home/user/pipeline
./step1_primer_extract.sh
./step2_alignment_filter.sh
./step3_graph_build.sh
EOF

    chmod +x step1_primer_extract.sh step2_alignment_filter.sh step3_graph_build.sh orchestrator.sh

    chmod -R 777 /home/user
