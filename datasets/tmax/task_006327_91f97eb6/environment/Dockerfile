FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:fdf9b7e5a762
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
