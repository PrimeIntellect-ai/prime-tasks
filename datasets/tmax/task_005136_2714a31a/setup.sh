#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets.csv
id,name
1,Raw_Climate_Data
2,Cleaned_Climate_Data
3,Regional_Aggregates
4,Global_Aggregates
5,Global_Warming_Model
6,Anomaly_Detection
7,Visualization_Dashboard
EOF

    cat << 'EOF' > /home/user/relationships.csv
source_id,target_id,transformation
1,2,Filter
2,3,GroupBy
3,4,Merge
4,5,Train
2,6,Detect
6,5,Feedback
1,7,Plot
4,7,Plot
EOF

    cat << 'EOF' > /home/user/extract_edges.sh
#!/bin/bash
tail -n +2 relationships.csv | while IFS=',' read -r src tgt trans; do
    tail -n +2 datasets.csv | while IFS=',' read -r id1 name1; do
        tail -n +2 datasets.csv | while IFS=',' read -r id2 name2; do
            echo "$name1|$name2|$trans"
        done
    done
done
EOF

    chmod +x /home/user/extract_edges.sh
    chmod -R 777 /home/user
