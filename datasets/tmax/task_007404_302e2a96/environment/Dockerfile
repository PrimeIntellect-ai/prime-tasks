FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e33d8127da7f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
