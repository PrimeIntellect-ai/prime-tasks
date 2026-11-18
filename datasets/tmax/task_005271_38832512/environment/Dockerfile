FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:65713a12ef31
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
