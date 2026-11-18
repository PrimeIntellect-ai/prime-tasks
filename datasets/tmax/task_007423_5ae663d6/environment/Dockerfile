FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:55e6c60749f4
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
