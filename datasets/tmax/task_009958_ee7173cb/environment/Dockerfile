FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:9850ab7b82a1
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
