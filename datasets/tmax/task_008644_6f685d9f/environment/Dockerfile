FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3c0cee62e7cc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
