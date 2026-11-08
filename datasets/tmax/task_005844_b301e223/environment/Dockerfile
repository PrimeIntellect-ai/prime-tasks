FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d5caa2b0e65a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
