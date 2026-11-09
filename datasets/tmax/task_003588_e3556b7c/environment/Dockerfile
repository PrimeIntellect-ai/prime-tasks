FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b71d6f312f37
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
