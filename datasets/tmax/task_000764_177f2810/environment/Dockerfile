FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:93af1b1b6790
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
