FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f908c0b09d39
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
