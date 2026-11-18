FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0a4b2b8c1dfc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
