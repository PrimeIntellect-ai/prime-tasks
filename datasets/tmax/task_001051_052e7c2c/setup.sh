#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct __attribute__((packed)) {
    uint64_t timestamp;
    uint32_t metric_id;
    uint32_t is_retry;
    double value;
} InputRecord;

typedef struct __attribute__((packed)) {
    uint64_t window_end_ts;
    uint32_t metric_id;
    double rolling_sum;
} OutputRecord;

typedef struct {
    InputRecord rec;
    int index;
} IndexedRecord;

IndexedRecord irecords[2000000];
int num_records = 0;

int compare_irecords(const void *a, const void *b) {
    IndexedRecord *ra = (IndexedRecord *)a;
    IndexedRecord *rb = (IndexedRecord *)b;
    if (ra->rec.metric_id != rb->rec.metric_id) return (ra->rec.metric_id < rb->rec.metric_id) ? -1 : 1;
    if (ra->rec.timestamp != rb->rec.timestamp) return (ra->rec.timestamp < rb->rec.timestamp) ? -1 : 1;
    return 0;
}

int main() {
    InputRecord r;
    while (fread(&r, sizeof(InputRecord), 1, stdin) == 1) {
        if (num_records < 2000000) {
            irecords[num_records].rec = r;
            irecords[num_records].index = num_records;
            num_records++;
        }
    }

    qsort(irecords, num_records, sizeof(IndexedRecord), compare_irecords);

    int i = 0;
    while (i < num_records) {
        int j = i;
        while (j < num_records && irecords[j].rec.metric_id == irecords[i].rec.metric_id) {
            j++;
        }

        int dedup_count = 0;
        InputRecord *dedup = malloc((j - i) * sizeof(InputRecord));
        for (int k = i; k < j; ) {
            int l = k;
            InputRecord best = irecords[k].rec;
            int best_idx = irecords[k].index;
            while (l < j && irecords[l].rec.timestamp == irecords[k].rec.timestamp) {
                if (irecords[l].rec.is_retry > best.is_retry || 
                   (irecords[l].rec.is_retry == best.is_retry && irecords[l].index > best_idx)) {
                    best = irecords[l].rec;
                    best_idx = irecords[l].index;
                }
                l++;
            }
            dedup[dedup_count++] = best;
            k = l;
        }

        uint64_t start_ts = dedup[0].timestamp;
        uint64_t end_ts = dedup[dedup_count-1].timestamp;

        double history[5] = {0};
        int hist_count = 0;

        int dedup_idx = 0;
        double current_val = dedup[0].value;

        for (uint64_t ts = start_ts; ts <= end_ts; ts++) {
            if (dedup_idx < dedup_count && dedup[dedup_idx].timestamp == ts) {
                current_val = dedup[dedup_idx].value;
                dedup_idx++;
            }

            for(int h=4; h>0; h--) history[h] = history[h-1];
            history[0] = current_val;
            if (hist_count < 5) hist_count++;

            double sum = 0;
            for(int h=0; h<hist_count; h++) sum += history[h];

            OutputRecord out;
            out.window_end_ts = ts;
            out.metric_id = dedup[0].metric_id;
            out.rolling_sum = sum;
            fwrite(&out, sizeof(OutputRecord), 1, stdout);
        }

        free(dedup);
        i = j;
    }

    return 0;
}
EOF

    gcc -O3 /tmp/legacy.c -o /app/legacy_aggregator
    strip /app/legacy_aggregator
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
