FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d0ed81e5a6a1
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
