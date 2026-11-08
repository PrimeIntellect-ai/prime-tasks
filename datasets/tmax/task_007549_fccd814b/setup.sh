#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    echo "x,y,value" > /home/user/observations.csv
    echo "x,y,value" > /home/user/reference.csv

    for x in {0..9}; do
      for y in {0..9}; do
        # Reference logic
        if [[ $x -le 4 && $y -le 4 ]]; then
          ref_val=10.0
        elif [[ $x -ge 5 && $y -le 4 ]]; then
          ref_val=$(echo "$x + $y" | bc -l)
        elif [[ $x -le 4 && $y -ge 5 ]]; then
          ref_val=$(echo "$x + $y" | bc -l)
        else
          ref_val=$(echo "$x * $y" | bc -l)
        fi
        echo "$x,$y,$ref_val" >> /home/user/reference.csv

        # Observations logic
        if [[ $x -le 4 && $y -le 4 ]]; then
          # Q1: Flat -> Singular
          obs_val=10.0
        elif [[ $x -ge 5 && $y -le 4 ]]; then
          # Q2: Matches reference -> Valid
          obs_val=$(echo "$x + $y" | bc -l)
        elif [[ $x -le 4 && $y -ge 5 ]]; then
          # Q3: 2 * (x+y) -> Mean absolute diff > 5.0 -> Anomalous
          obs_val=$(echo "2 * ($x + $y)" | bc -l)
        else
          # Q4: Matches reference -> Valid
          obs_val=$(echo "$x * $y" | bc -l)
        fi
        echo "$x,$y,$obs_val" >> /home/user/observations.csv
      done
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
