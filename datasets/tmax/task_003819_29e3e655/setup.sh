#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1_exact_match
ATGGACTGGCCTAGGGCC
>seq2_one_mismatch
ATGGACTGTCCTAGGGCC
>seq3_two_mismatches_ignore
ATGGACTATCCTAGGGCC
>seq4_no_match
AAAAAAAAAAAAAAAAAA
>seq5_exact_match_end
GCGCGCGCGACTGGCCTA
>seq6_one_mismatch_start
ACTGGCCTCGATCGATCG
>seq7_exact_match_middle
TTTACTGGCCTATTTAAA
>seq8_one_mismatch_middle
TTTACTAGCCTATTTAAA
>seq9_exact
ACTGGCCTAACTGGCCTA
>seq10_one_mis_long
GGGGGGGGGGACTGGCCTCGGGGGGGGGG
EOF

    chmod -R 777 /home/user
