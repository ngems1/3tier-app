"""MySQL connection handling.

Credentials come either from the environment (local) or from the RDS-managed
Secrets Manager secret (AWS). RDS rotates that secret automatically, so when
MySQL rejects the cached password the secret is re-read once and the
connection retried.
"""

from __future__ import annotations

import json
import logging
import threading
from collections.abc import Iterator
from contextlib import contextmanager

import pymysql
from pymysql.cursors import DictCursor

from .config import Settings

log = logging.getLogger(__name__)

ACCESS_DENIED = 1045


class CredentialProvider:
    def __init__(self, settings: Settings, secrets_client=None) -> None:
        self._settings = settings
        self._client = secrets_client
        self._lock = threading.Lock()
        self._cached: tuple[str, str] | None = None

    def get(self) -> tuple[str, str]:
        if not self._settings.uses_secrets_manager:
            return self._settings.db_user or "", self._settings.db_password or ""
        with self._lock:
            if self._cached is None:
                self._cached = self._fetch()
            return self._cached

    def invalidate(self) -> None:
        with self._lock:
            self._cached = None

    def _fetch(self) -> tuple[str, str]:
        client = self._client
        if client is None:
            import boto3  # imported lazily so local runs and tests don't need it

            client = boto3.client("secretsmanager", region_name=self._settings.aws_region)
            self._client = client
        response = client.get_secret_value(SecretId=self._settings.db_secret_arn)
        secret = json.loads(response["SecretString"])
        log.info("Loaded database credentials from Secrets Manager")
        return secret["username"], secret["password"]


class Database:
    def __init__(self, settings: Settings, credentials: CredentialProvider, connect=pymysql.connect) -> None:
        self._settings = settings
        self._credentials = credentials
        self._connect = connect

    def _open(self):
        user, password = self._credentials.get()
        options = {
            "host": self._settings.db_host,
            "port": self._settings.db_port,
            "user": user,
            "password": password,
            "database": self._settings.db_name,
            "cursorclass": DictCursor,
            "autocommit": True,
            "charset": "utf8mb4",
            "connect_timeout": 5,
            "read_timeout": 10,
            "write_timeout": 10,
        }
        if self._settings.db_ssl_ca:
            # Encrypt data in transit and verify the RDS server certificate.
            # Pass the CA as ssl_ca: when any ssl_* argument is given, PyMySQL
            # rebuilds its SSL settings from the ssl_* arguments alone and
            # ignores an ssl={"ca": ...} dict, which would fall back to the
            # system trust store (no RDS CA -> CERTIFICATE_VERIFY_FAILED).
            options["ssl_ca"] = self._settings.db_ssl_ca
            options["ssl_verify_cert"] = True
            options["ssl_verify_identity"] = True
        return self._connect(**options)

    @contextmanager
    def connection(self) -> Iterator[pymysql.connections.Connection]:
        try:
            conn = self._open()
        except pymysql.err.OperationalError as exc:
            if exc.args and exc.args[0] == ACCESS_DENIED and self._settings.uses_secrets_manager:
                log.warning("Database rejected cached credentials; reloading secret (possible rotation)")
                self._credentials.invalidate()
                conn = self._open()
            else:
                raise
        try:
            yield conn
        finally:
            conn.close()
