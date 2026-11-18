FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0fe6b03c6667
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
