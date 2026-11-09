FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:bb0c1b3c2580
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
