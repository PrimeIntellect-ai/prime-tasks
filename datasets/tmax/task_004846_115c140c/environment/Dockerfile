FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d2982e5d1e7e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
