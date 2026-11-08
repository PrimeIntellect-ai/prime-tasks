FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:2056d9225f87
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
