#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create sequences.fasta
    cat << 'EOF' > sequences.fasta
>Seq1
ATGCGTACGTAGCTAG
>Seq2
ATGCGTACGTAGCTAG
>Seq3
GGGGGGGGGGGGGGGG
>Seq4
ATGCATGCATGCATGC
EOF

    # Create analyze_network.sh
    cat << 'EOF' > analyze_network.sh
#!/bin/bash
# analyze_network.sh
# Calculates 2-mer distribution L1 distance and edge weights

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <fasta_file>"
    exit 1
fi

FILE=$1

awk '
/^>/ {
    id = substr($1, 2);
    seqs[id] = "";
    curr = id;
    next;
}
{
    seqs[curr] = seqs[curr] $0;
}
END {
    # Count 2-mers
    for (id in seqs) {
        len = length(seqs[id]);
        total[id] = len - 1;
        for (i=1; i<len; i++) {
            kmer = substr(seqs[id], i, 2);
            counts[id, kmer]++;
        }
    }

    # Calculate distances and weights
    for (id1 in seqs) {
        for (id2 in seqs) {
            if (id1 < id2) {
                dist = 0;
                # all possible 2-mers (simplified loop over found ones)
                for (c in counts) {
                    split(c, parts, SUBSEP);
                    if (parts[1] == id1) all_kmers[parts[2]] = 1;
                    if (parts[1] == id2) all_kmers[parts[2]] = 1;
                }

                for (k in all_kmers) {
                    p1 = (counts[id1, k] ? counts[id1, k] : 0) / total[id1];
                    p2 = (counts[id2, k] ? counts[id2, k] : 0) / total[id2];
                    diff = p1 - p2;
                    if (diff < 0) diff = -diff;
                    dist += diff;
                }

                # BUG: Division by zero when dist == 0
                weight = 1.0 / dist;

                printf "%s\t%s\t%.2f\n", id1, id2, weight;
                delete all_kmers;
            }
        }
    }
}
' "$FILE" > edges.tsv
EOF
    chmod +x analyze_network.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
