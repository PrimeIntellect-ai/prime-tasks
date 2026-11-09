FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:98fb1ad5c23f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
