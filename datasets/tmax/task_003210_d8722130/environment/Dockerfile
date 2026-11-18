FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d2c8a7dc253d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
