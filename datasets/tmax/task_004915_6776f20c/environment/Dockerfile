FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5d6a451a50c0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
