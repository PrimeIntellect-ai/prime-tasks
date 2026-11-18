FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:de1f0f7fa46f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
