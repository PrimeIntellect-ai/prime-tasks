FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:58b9b15b43ff
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
