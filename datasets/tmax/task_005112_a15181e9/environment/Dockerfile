FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:59a5f52d1069
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
