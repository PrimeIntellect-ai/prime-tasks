FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8fd20d1e323d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
