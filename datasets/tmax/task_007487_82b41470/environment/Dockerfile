FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a3c2b26c5bab
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
