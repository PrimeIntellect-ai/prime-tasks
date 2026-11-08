FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:fd9b701b1de0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
