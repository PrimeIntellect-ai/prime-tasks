FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:2e3b2f7cde2b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
