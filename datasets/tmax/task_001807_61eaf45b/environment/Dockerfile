FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5777e9055c2e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
