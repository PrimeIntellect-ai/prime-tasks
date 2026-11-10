FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

# Bootstrap HTTPS trust from another immutable image; the minimal Ubuntu base
# has no CA bundle. APT still verifies the archive's signed package metadata.
COPY --from=python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Both evaluation routes build this exact calculation environment. The dated
# Ubuntu archive also fixes transitive packages, not just LibreOffice's version.
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
RUN printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260911T000000Z noble main universe' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260911T000000Z noble-updates main universe' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260911T000000Z noble-security main universe' \
      > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       libreoffice-calc=4:24.2.7-0ubuntu0.24.04.6 \
       python3-uno=4:24.2.7-0ubuntu0.24.04.6 python3-venv libseccomp2 ca-certificates \
       fonts-dejavu-core fonts-liberation \
    && rm -rf /var/lib/apt/lists/* \
    && printf '%s\n' 'libreoffice-24.2.7.2-ubuntu24.04.6-snapshot20260911' > /opt/jobbench-calc-runtime

ENV JOBBENCH_CALC_NATIVE=1

# One dependency-only image is used for the solver and a fresh grading VM.
# Separate Python environments preserve both upstream dependency sets.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash curl file git jq tmux unzip zip sqlite3 poppler-utils tesseract-ocr \
       libreoffice pandoc gdal-bin libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*
COPY agent-requirements.txt verifier-requirements.txt /tmp/
RUN python3 -m venv /opt/jobbench-agent \
    && /opt/jobbench-agent/bin/pip install --no-cache-dir -r /tmp/agent-requirements.txt \
    && python3 -m venv /opt/jobbench-verifier \
    && /opt/jobbench-verifier/bin/pip install --no-cache-dir -r /tmp/verifier-requirements.txt \
    && rm /tmp/agent-requirements.txt /tmp/verifier-requirements.txt
ENV PATH="/opt/jobbench-agent/bin:${PATH}" MPLBACKEND=Agg
RUN mkdir -p /workspace/task_folder /workspace/output && chmod 0777 /workspace/output
WORKDIR /workspace
