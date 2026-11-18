FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:000d2b03b33d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
