FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b5b983144a5f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
