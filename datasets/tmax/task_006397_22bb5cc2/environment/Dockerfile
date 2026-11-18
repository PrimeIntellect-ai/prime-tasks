FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e555d060f7ce
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
