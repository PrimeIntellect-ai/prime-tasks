FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b1d25c9ed1b7
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
