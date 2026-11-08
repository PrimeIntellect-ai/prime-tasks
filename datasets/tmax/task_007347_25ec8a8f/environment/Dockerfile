FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:521d5c6ec4a0
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
