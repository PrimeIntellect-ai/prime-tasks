FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:828b5b6e7d35
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
