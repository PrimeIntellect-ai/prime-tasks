FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a4d74645b2f5
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
