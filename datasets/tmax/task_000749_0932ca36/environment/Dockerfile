FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:30e3b7d6f7f5
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
