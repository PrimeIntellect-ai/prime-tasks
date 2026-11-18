FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6b178d8a7cce
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
