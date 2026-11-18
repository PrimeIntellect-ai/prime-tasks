FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0ba14e3e653c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
