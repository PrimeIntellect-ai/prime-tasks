FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:1d7d4c194774
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
