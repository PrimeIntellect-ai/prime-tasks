FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:faf1f1b8a739
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
