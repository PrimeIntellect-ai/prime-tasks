FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ef3d8d1f1a24
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
