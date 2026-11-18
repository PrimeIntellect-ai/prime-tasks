FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e46e0a90e8c8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
