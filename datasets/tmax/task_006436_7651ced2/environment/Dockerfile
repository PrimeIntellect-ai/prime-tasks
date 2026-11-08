FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3b0e0d2292e9
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
