# syntax=docker/dockerfile:1

# ---- build stage: install pinned dependencies into a virtualenv ----
FROM python:3.11-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
# Install the app's dependencies, then remove the packaging tools (pip,
# setuptools, wheel) from the virtualenv: the app never needs them at runtime,
# and they bundle libraries with known vulnerabilities (e.g. wheel,
# jaraco.context inside setuptools).
RUN /opt/venv/bin/pip install -r /tmp/requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip setuptools wheel
# Amazon RDS CA bundle, so the API can verify the database's TLS certificate.
RUN python -c "import urllib.request; urllib.request.urlretrieve('https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem', '/tmp/rds-global-bundle.pem')"

# ---- runtime stage: slim image, non-root user ----
FROM python:3.11-slim
# The base image's own packaging tools aren't needed at runtime either.
RUN python -m pip uninstall -y pip setuptools wheel
ENV PATH="/opt/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN groupadd --system app && useradd --system --gid app --no-create-home app
COPY --from=build /opt/venv /opt/venv
COPY --from=build /tmp/rds-global-bundle.pem /etc/pki/rds/global-bundle.pem
WORKDIR /srv
COPY app ./app

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.version=${APP_VERSION}

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
