FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:bb90e5f1c061
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
