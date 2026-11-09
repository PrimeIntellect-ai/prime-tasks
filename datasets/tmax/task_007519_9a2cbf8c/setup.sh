#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reference_primers.txt
ACGTACGTACGTACG
TGCATGCATGCATGC
GGCCAATTGGCCAAT
EOF

    cat << 'EOF' > /home/user/primers.txt
ATGCATGCATGCATG
CGTACGTACGTACGT
AATTGCCGGCCAATT
EOF

    cat << 'EOF' > /home/user/reference_sv.txt
14.248
EOF

    cat << 'EOF' > /home/user/test_regression.sh
#!/bin/bash
g++ -O3 /home/user/spectral_align.cpp -o /home/user/spectral_align
if [ $? -ne 0 ]; then
    echo "Compilation failed."
    exit 1
fi

OUTPUT=$(/home/user/spectral_align /home/user/reference_primers.txt)
EXPECTED=$(cat /home/user/reference_sv.txt)

if [ "$OUTPUT" == "$EXPECTED" ]; then
    echo "Regression test PASSED."
    exit 0
else
    echo "Regression test FAILED. Expected $EXPECTED, got $OUTPUT."
    exit 1
fi
EOF
    chmod +x /home/user/test_regression.sh

    cat << 'EOF' > /home/user/spectral_align.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <iomanip>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <sequences.txt>" << endl;
        return 1;
    }
    ifstream in(argv[1]);
    vector<string> seqs;
    string s;
    while(in >> s) seqs.push_back(s);

    if(seqs.empty()) return 1;

    int n = seqs.size();
    int m = seqs[0].size();
    vector<vector<double>> M(n, vector<double>(m, 0.0));
    for(int i=0; i<n; ++i) {
        for(int j=0; j<m; ++j) {
            if(seqs[i][j] == 'A') M[i][j] = 1.0;
            else if(seqs[i][j] == 'C') M[i][j] = -1.0;
            else if(seqs[i][j] == 'G') M[i][j] = 2.0;
            else if(seqs[i][j] == 'T') M[i][j] = -2.0;
        }
    }

    // A = M^T M
    vector<vector<double>> A(m, vector<double>(m, 0.0));
    for(int i=0; i<m; ++i) {
        for(int j=0; j<m; ++j) {
            for(int k=0; k<n; ++k) {
                A[i][j] += M[k][i] * M[k][j];
            }
        }
    }

    // Power method to find dominant eigenvalue of A
    vector<double> v(m, 1.0);
    for(int iter=0; iter<1000; ++iter) {
        vector<double> u(m, 0.0);
        double norm = 0.0;
        for(int i=0; i<m; ++i) {
            for(int j=0; j<m; ++j) {
                u[i] += A[i][j] * v[j];
            }
            norm += u[i]*u[i];
        }
        norm = sqrt(norm);
        for(int i=0; i<m; ++i) v[i] = u[i]/norm;
    }

    // Rayleigh quotient
    double lambda = 0.0;
    for(int i=0; i<m; ++i) {
        double Av_i = 0.0;
        for(int j=0; j<m; ++j) {
            Av_i += A[i][j] * v[j];
        }
        lambda += v[i] * Av_i;
    }

    // BUG: The spectral norm (top singular value) of M is the square root of the top eigenvalue of M^T M.
    // The code currently prints lambda (the eigenvalue), not sqrt(lambda).
    cout << fixed << setprecision(3) << lambda << endl;

    return 0;
}
EOF

    chmod -R 777 /home/user
