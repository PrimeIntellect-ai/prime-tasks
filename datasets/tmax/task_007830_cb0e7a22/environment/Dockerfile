FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6010a8d25e85
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
