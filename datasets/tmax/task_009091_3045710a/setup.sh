#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate mock data
    awk 'BEGIN {
      srand(42);
      for(i=1; i<=1000; i++) {
        col1 = i;
        col2 = int(rand() * 100);
        col3 = int(rand() * 1000);
        col4 = int(rand() * 2);
        col5 = "CORRUPT";
        if (i == 950) { col3 = 9999; }
        if (i == 150) { col3 = -500; }
        print col1 "," col2 "," col3 "," col4 "," col5;
      }
    }' > /home/user/dataset.csv

    # Ensure the test set has the true global max, and the train set has a different max
    awk 'BEGIN { FS=OFS="," } {
      if (NR == 900) $3 = 5000;
      if (NR == 901) $3 = -1000;
      if (NR == 100) $3 = 4000;
      if (NR == 101) $3 = -500;
      print $0
    }' /home/user/dataset.csv > /home/user/dataset.tmp && mv /home/user/dataset.tmp /home/user/dataset.csv

    # Create flawed pipeline.sh
    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
# Flawed script

# Get min and max of col 3 (Leakage!)
MIN=$(awk -F, 'NR==1{min=$3} $3<min{min=$3} END{print min}' /home/user/dataset.csv)
MAX=$(awk -F, 'NR==1{max=$3} $3>max{max=$3} END{print max}' /home/user/dataset.csv)

# Scale and keep all columns (Failed feature selection)
awk -v min="$MIN" -v max="$MAX" -F, 'BEGIN{OFS=","} {
  $3 = sprintf("%.4f", ($3 - min) / (max - min));
  print $0
}' /home/user/dataset.csv > /home/user/processed_all.csv

head -n 800 /home/user/processed_all.csv > /home/user/train_processed.csv
tail -n 200 /home/user/processed_all.csv > /home/user/test_processed.csv
EOF

    chmod +x /home/user/pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
