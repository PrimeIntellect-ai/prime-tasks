FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e4e3a66d4b5c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
