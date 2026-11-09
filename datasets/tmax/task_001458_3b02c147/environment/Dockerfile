FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:29d0837ad1a8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
