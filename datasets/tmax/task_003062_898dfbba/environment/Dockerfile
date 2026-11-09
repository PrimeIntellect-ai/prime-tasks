FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:80a1d02f3779
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
