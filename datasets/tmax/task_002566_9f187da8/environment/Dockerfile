FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:cbe92d9f51f6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
