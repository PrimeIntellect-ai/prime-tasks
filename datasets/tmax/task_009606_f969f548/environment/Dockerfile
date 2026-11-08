FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3d55d8ddc20f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
