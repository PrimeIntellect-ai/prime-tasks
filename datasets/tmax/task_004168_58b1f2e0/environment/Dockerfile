FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:75c7f1894375
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
