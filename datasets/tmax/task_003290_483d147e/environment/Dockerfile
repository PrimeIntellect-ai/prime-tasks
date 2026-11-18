FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8dd75ddd3d70
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
