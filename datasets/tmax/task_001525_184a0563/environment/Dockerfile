FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b7554e7f2ebe
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
