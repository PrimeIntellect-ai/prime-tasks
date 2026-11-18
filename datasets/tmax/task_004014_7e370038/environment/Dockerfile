FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:eb981a37f22c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
