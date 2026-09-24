"""Environment-based configuration.

Every setting comes from an environment variable so the same build runs
locally (Docker Compose), in CI, and on EC2 without code changes:

* Local / CI: DB_USER and DB_PASSWORD are passed directly.
* AWS: DB_SECRET_ARN points at the RDS-managed Secrets Manager secret and the
  credentials are fetched (and refreshed after rotation) at runtime.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_user: str | None
    db_password: str | None
    db_secret_arn: str | None
    db_ssl_ca: str | None
    aws_region: str | None
    app_version: str
    init_schema: bool

    @property
    def uses_secrets_manager(self) -> bool:
        return bool(self.db_secret_arn)


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def load_settings() -> Settings:
    secret_arn = os.environ.get("DB_SECRET_ARN", "").strip() or None
    user = os.environ.get("DB_USER", "").strip() or None
    password = os.environ.get("DB_PASSWORD") or None

    if not secret_arn and not (user and password):
        raise RuntimeError(
            "Database credentials are not configured: set DB_SECRET_ARN (AWS) "
            "or DB_USER and DB_PASSWORD (local development)"
        )

    return Settings(
        db_host=_require("DB_HOST"),
        db_port=int(os.environ.get("DB_PORT", "3306")),
        db_name=os.environ.get("DB_NAME", "webappdb"),
        db_user=user,
        db_password=password,
        db_secret_arn=secret_arn,
        db_ssl_ca=os.environ.get("DB_SSL_CA", "").strip() or None,
        aws_region=os.environ.get("AWS_REGION", "").strip() or None,
        app_version=os.environ.get("APP_VERSION", "dev"),
        init_schema=os.environ.get("DB_INIT_SCHEMA", "true").lower() == "true",
    )
