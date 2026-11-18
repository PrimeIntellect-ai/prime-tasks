FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c8e8ca9c5ad6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
