#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate the video
    cat > generate_video.sh << 'EOF'
#!/bin/bash
intensities=(100 101 102 103 101 102 103 104 102 103 104 105 103 104 105 106)
echo "" > list.txt
for i in "${!intensities[@]}"; do
    val=${intensities[$i]}
    hex=$(printf "%02x" $val)
    ffmpeg -f lavfi -i color=c=#${hex}${hex}${hex}:s=100x100:d=1 -c:v libx264 -y temp_$i.mp4 2>/dev/null
    echo "file 'temp_$i.mp4'" >> list.txt
done
ffmpeg -f concat -safe 0 -i list.txt -c copy /app/matrix.mp4 2>/dev/null
rm temp_*.mp4 list.txt
EOF
    chmod +x generate_video.sh
    ./generate_video.sh

    # Create oracle
    cat > oracle_eval_primer.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *seq = argv[1];
    double b[4] = {0};
    for (int i = 0; seq[i]; i++) {
        if (seq[i] == 'A') b[0]++;
        else if (seq[i] == 'C') b[1]++;
        else if (seq[i] == 'G') b[2]++;
        else if (seq[i] == 'T') b[3]++;
    }

    double M[4][4] = {
        {100/255.0, 101/255.0, 102/255.0, 103/255.0},
        {101/255.0, 102/255.0, 103/255.0, 104/255.0},
        {102/255.0, 103/255.0, 104/255.0, 105/255.0},
        {103/255.0, 104/255.0, 105/255.0, 106/255.0}
    };

    double MtM[4][4] = {0};
    for(int i=0; i<4; i++) {
        for(int j=0; j<4; j++) {
            for(int k=0; k<4; k++) {
                MtM[i][j] += M[k][i] * M[k][j];
            }
        }
    }

    double lambda = 0.05;
    for(int i=0; i<4; i++) {
        MtM[i][i] += lambda;
    }

    double Mtb[4] = {0};
    for(int i=0; i<4; i++) {
        for(int k=0; k<4; k++) {
            Mtb[i] += M[k][i] * b[k];
        }
    }

    double A[4][5];
    for(int i=0; i<4; i++) {
        for(int j=0; j<4; j++) A[i][j] = MtM[i][j];
        A[i][4] = Mtb[i];
    }

    for (int i=0; i<4; i++) {
        int max = i;
        for (int k=i+1; k<4; k++) {
            if (fabs(A[k][i]) > fabs(A[max][i])) max = k;
        }
        for (int k=0; k<5; k++) {
            double tmp = A[i][k];
            A[i][k] = A[max][k];
            A[max][k] = tmp;
        }
        for (int k=i+1; k<4; k++) {
            double f = A[k][i] / A[i][i];
            for (int j=i; j<5; j++) {
                A[k][j] -= A[i][j] * f;
            }
        }
    }

    double x[4];
    for (int i=3; i>=0; i--) {
        x[i] = A[i][4];
        for (int j=i+1; j<4; j++) {
            x[i] -= A[i][j] * x[j];
        }
        x[i] /= A[i][i];
    }

    printf("%.6f %.6f %.6f %.6f\n", x[0], x[1], x[2], x[3]);
    return 0;
}
EOF
    gcc -O3 -o /app/oracle_eval_primer oracle_eval_primer.c -lm

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
