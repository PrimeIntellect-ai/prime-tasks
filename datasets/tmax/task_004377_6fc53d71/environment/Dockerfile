FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:920c0e6c7da0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
