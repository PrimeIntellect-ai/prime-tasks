FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:970da170af76
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
