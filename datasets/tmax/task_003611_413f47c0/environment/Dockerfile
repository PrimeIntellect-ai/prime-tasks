FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5a9658d8fd85
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
