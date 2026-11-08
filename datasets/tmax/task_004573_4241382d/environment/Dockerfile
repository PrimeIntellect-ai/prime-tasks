FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:119a4a2d211a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
