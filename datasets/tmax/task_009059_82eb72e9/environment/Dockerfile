FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:86f2b6f92fb9
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
