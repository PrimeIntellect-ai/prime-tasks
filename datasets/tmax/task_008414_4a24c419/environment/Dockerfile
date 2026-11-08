FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6ca1aa0e36fd
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
