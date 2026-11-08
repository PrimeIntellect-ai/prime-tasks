#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libmicrohttpd-dev \
        build-essential

    pip3 install pytest requests matplotlib pandas

    mkdir -p /app/frames

    # Generate test video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x360:rate=10 -pix_fmt yuv420p /app/sensor_data.mp4

    # Create analyzer.c
    cat << 'EOF' > /app/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <microhttpd.h>

#define WIDTH 640
#define HEIGHT 360
#define NUM_THREADS 4

double global_sum = 0.0;
pthread_mutex_t lock;

typedef struct {
    double* matrix;
    int start_col;
    int end_col;
} ThreadData;

void* compute_sum(void* arg) {
    ThreadData* data = (ThreadData*)arg;
    double local_sum = 0.0;
    for (int j = data->start_col; j < data->end_col; j++) {
        double col_sum = 0.0;
        for (int i = 0; i < HEIGHT; i++) {
            col_sum += data->matrix[i * WIDTH + j];
        }
        local_sum += col_sum * (j + 1); // weighted sum
    }

    pthread_mutex_lock(&lock);
    global_sum += local_sum;
    pthread_mutex_unlock(&lock);

    return NULL;
}

static enum MHD_Result answer_to_connection(void *cls, struct MHD_Connection *connection,
                          const char *url, const char *method,
                          const char *version, const char *upload_data,
                          size_t *upload_data_size, void **con_cls) {
    const char *frame_str = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "frame");
    if (!frame_str) return MHD_NO;

    int frame = atoi(frame_str);
    char filename[256];
    sprintf(filename, "/app/frames/frame_%d.gray", frame);

    FILE *f = fopen(filename, "rb");
    if (!f) return MHD_NO;

    unsigned char *raw = malloc(WIDTH * HEIGHT);
    fread(raw, 1, WIDTH * HEIGHT, f);
    fclose(f);

    double *matrix = malloc(WIDTH * HEIGHT * sizeof(double));
    for (int i = 0; i < WIDTH * HEIGHT; i++) {
        matrix[i] = (double)raw[i];
    }
    free(raw);

    global_sum = 0.0;
    pthread_mutex_init(&lock, NULL);

    pthread_t threads[NUM_THREADS];
    ThreadData tdata[NUM_THREADS];
    int cols_per_thread = WIDTH / NUM_THREADS;

    for (int i = 0; i < NUM_THREADS; i++) {
        tdata[i].matrix = matrix;
        tdata[i].start_col = i * cols_per_thread;
        tdata[i].end_col = (i == NUM_THREADS - 1) ? WIDTH : (i + 1) * cols_per_thread;
        pthread_create(&threads[i], NULL, compute_sum, &tdata[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    free(matrix);
    pthread_mutex_destroy(&lock);

    char response_str[256];
    sprintf(response_str, "%f", global_sum);

    struct MHD_Response *response = MHD_create_response_from_buffer(strlen(response_str), (void*)response_str, MHD_RESPMEM_MUST_COPY);
    enum MHD_Result ret = MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);

    return ret;
}

int main() {
    struct MHD_Daemon *daemon = MHD_start_daemon(MHD_USE_INTERNAL_POLLING_THREAD, 9090, NULL, NULL,
                                                 &answer_to_connection, NULL, MHD_OPTION_END);
    if (NULL == daemon) return 1;
    while (1) {
        sleep(1);
    }
    MHD_stop_daemon(daemon);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
