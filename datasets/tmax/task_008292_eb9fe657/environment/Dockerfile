FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:87c609de05d0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
