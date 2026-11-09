#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/raw.csv
age,income,score
25,40000,80
30,50000,85
22,35000,75
45,80000,90
50,90000,95
28,45000,78
35,60000,88
40,70000,92
26,42000,81
32,55000,86
23,38000,76
48,85000,94
55,95000,98
29,48000,82
38,65000,89
42,75000,93
27,44000,80
33,58000,87
24,39000,77
46,82000,91
52,92000,96
31,52000,84
36,62000,88
41,72000,92
26,41000,79
34,57000,86
21,34000,74
47,84000,93
53,94000,97
30,51000,83
37,64000,89
43,76000,94
28,46000,81
35,60000,87
22,36000,75
49,86000,95
54,96000,99
32,54000,85
39,68000,91
44,78000,95
25,43000,80
33,59000,88
23,37000,76
48,85000,93
56,98000,100
29,47000,82
38,66000,90
42,74000,93
27,45000,81
34,58000,87
24,40000,78
46,83000,92
52,93000,97
31,53000,84
36,63000,89
41,73000,92
26,42000,80
35,61000,88
21,35000,74
47,84000,94
53,95000,98
30,52000,83
37,65000,90
43,77000,95
28,47000,82
36,61000,88
22,37000,76
49,87000,96
54,97000,99
32,55000,86
39,69000,92
44,79000,96
25,44000,81
33,60000,89
23,38000,77
48,86000,94
56,99000,100
29,48000,83
38,67000,91
42,75000,94
27,46000,82
34,59000,88
24,41000,79
46,84000,93
52,94000,98
31,54000,85
36,64000,90
41,74000,93
26,43000,81
35,62000,89
21,36000,75
47,85000,95
53,96000,99
30,53000,84
37,66000,91
43,78000,96
28,48000,83
36,62000,89
22,38000,77
49,88000,97
EOF

cat << 'EOF' > /home/user/etl.sh
#!/bin/bash
# Schema validation
awk -F, 'NR>1 {if(NF!=3 || $1!~/[0-9]+/ || $2!~/[0-9]+/ || $3!~/[0-9]+/) {print "Schema error"; exit 1}}' /home/user/data/raw.csv

# Find global min and max (LEAKAGE!)
mins_maxs=$(awk -F, 'NR==2 {min1=max1=$1; min2=max2=$2; min3=max3=$3} NR>2 {if($1<min1) min1=$1; if($1>max1) max1=$1; if($2<min2) min2=$2; if($2>max2) max2=$2; if($3<min3) min3=$3; if($3>max3) max3=$3} END {print min1, max1, min2, max2, min3, max3}' /home/user/data/raw.csv)

read min1 max1 min2 max2 min3 max3 <<< "$mins_maxs"

# Scale and predict
awk -F, -v min1=$min1 -v max1=$max1 -v min2=$min2 -v max2=$max2 -v min3=$min3 -v max3=$max3 '
NR>1 {
    s1 = ($1 - min1) / (max1 - min1)
    s2 = ($2 - min2) / (max2 - min2)
    s3 = ($3 - min3) / (max3 - min3)
    if (NR > 81) {
        # test set inference
        pred = 5.0 + (2.5 * s1) + (0.5 * s2) + (-1.2 * s3)
        print pred
    }
}' /home/user/data/raw.csv > /home/user/predictions.txt
EOF

chmod +x /home/user/etl.sh
chmod -R 777 /home/user
