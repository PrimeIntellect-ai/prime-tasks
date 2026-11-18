FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:300d3182f183
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
