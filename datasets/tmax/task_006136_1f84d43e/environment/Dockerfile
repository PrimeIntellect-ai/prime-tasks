FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3b1b2051b3bb
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
