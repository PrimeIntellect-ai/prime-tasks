FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f20c29914a9d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
