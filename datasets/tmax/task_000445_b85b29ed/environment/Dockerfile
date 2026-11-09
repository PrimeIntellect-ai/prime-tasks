FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c3a6d8e2c3d8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
