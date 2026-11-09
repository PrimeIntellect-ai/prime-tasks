FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:59e7d445e87a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
