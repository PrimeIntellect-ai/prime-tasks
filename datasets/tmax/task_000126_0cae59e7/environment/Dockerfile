FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:849c8c7c5260
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
