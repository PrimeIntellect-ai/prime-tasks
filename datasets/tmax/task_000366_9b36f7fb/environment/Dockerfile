FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:27bb4f5a5088
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
