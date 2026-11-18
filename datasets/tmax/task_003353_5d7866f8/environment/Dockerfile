FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a22c9d0a8293
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
