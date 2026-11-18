#!/bin/bash
IFS=',' read -ra loads <<< "$1"
min=${loads[0]}
max=${loads[0]}
sum=0
count=${#loads[@]}

for val in "${loads[@]}"; do
    (( val < min )) && min=$val
    (( val > max )) && max=$val
    sum=$((sum + val))
done
avg=$((sum / count))

pop=("$min" "$max" "$avg")

for ((i=0; i<10; i++)); do
    best_t=-1
    best_fit=-1

    for t in "${pop[@]}"; do
        fit=0
        for val in "${loads[@]}"; do
            diff=$((t - val))
            (( diff < 0 )) && diff=$((diff * -1))
            fit=$((fit + diff))
        done

        if [[ $best_fit -eq -1 ]] || (( fit < best_fit )) || ( (( fit == best_fit )) && (( t < best_t )) ); then
            best_fit=$fit
            best_t=$t
        fi
    done

    pop=("$best_t" "$((best_t - 5))" "$((best_t + 5))")
done

echo "$best_t"
