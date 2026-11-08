FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:9241f3d9191d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
