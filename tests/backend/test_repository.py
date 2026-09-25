"""Repository and connection tests using a fake PyMySQL connection, so they run
without a database."""

import json
from datetime import datetime

import pymysql
import pytest

from app.config import Settings
from app.db import CredentialProvider, Database
from app.models import TaskCreate, TaskUpdate
from app.repository import TaskRepository

ROW = {
    "id": 1,
    "title": "t",
    "description": None,
    "status": "todo",
    "created_at": datetime(2026, 1, 1),
    "updated_at": datetime(2026, 1, 1),
}


def settings(**overrides) -> Settings:
    values = {
        "db_host": "db",
        "db_port": 3306,
        "db_name": "webappdb",
        "db_user": "app",
        "db_password": "secret",
        "db_secret_arn": None,
        "db_ssl_ca": None,
        "aws_region": "us-east-1",
        "app_version": "test",
        "init_schema": False,
    }
    values.update(overrides)
    return Settings(**values)


class FakeCursor:
    def __init__(self, log):
        self.log = log
        self.lastrowid = 1
        self.rowcount = 1

    def execute(self, sql, params=None):
        self.log.append((" ".join(sql.split()), params))

    def fetchone(self):
        return ROW

    def fetchall(self):
        return [ROW]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeConnection:
    def __init__(self, log):
        self.log = log

    def cursor(self):
        return FakeCursor(self.log)

    def close(self):
        pass


@pytest.fixture
def queries():
    return []


@pytest.fixture
def repo(queries):
    cfg = settings()
    db = Database(cfg, CredentialProvider(cfg), connect=lambda **kw: FakeConnection(queries))
    return TaskRepository(db)


def test_user_input_is_always_bound_as_parameters(repo, queries):
    evil = "x'); DROP TABLE tasks; --"
    repo.create(TaskCreate(title=evil, description=evil))
    repo.update(1, TaskUpdate(title=evil))
    repo.get(1)
    repo.delete(1)

    for sql, _params in queries:
        assert evil not in sql
    assert queries[0] == (
        "INSERT INTO tasks (title, description, status) VALUES (%s, %s, %s)",
        (evil, evil, "todo"),
    )
    update_sql, update_params = queries[2]
    assert update_sql == "UPDATE tasks SET title = %s WHERE id = %s"
    assert update_params == [evil, 1]
    assert queries[-1] == ("DELETE FROM tasks WHERE id = %s", (1,))


def test_update_only_touches_fields_that_were_sent(repo, queries):
    repo.update(1, TaskUpdate(status="done", description=None))
    sql, params = queries[0]
    assert sql == "UPDATE tasks SET description = %s, status = %s WHERE id = %s"
    assert params == [None, "done", 1]


def test_tls_is_enabled_when_a_ca_bundle_is_configured():
    captured = {}
    cfg = settings(db_ssl_ca="/etc/pki/rds/global-bundle.pem")

    def connect(**kwargs):
        captured.update(kwargs)
        return FakeConnection([])

    with Database(cfg, CredentialProvider(cfg), connect=connect).connection():
        pass
    assert captured["ssl_ca"] == "/etc/pki/rds/global-bundle.pem"
    assert "ssl" not in captured  # PyMySQL ignores ssl={...} when ssl_* arguments are set
    assert captured["ssl_verify_cert"] is True


class FakeSecrets:
    def __init__(self, passwords):
        self.passwords = list(passwords)
        self.calls = 0

    def get_secret_value(self, SecretId):
        self.calls += 1
        return {"SecretString": json.dumps({"username": "admin", "password": self.passwords.pop(0)})}


def test_rotated_secret_is_reloaded_after_access_denied():
    cfg = settings(db_user=None, db_password=None, db_secret_arn="arn:aws:secretsmanager:x")
    secrets = FakeSecrets(["old", "new"])
    attempts = []

    def connect(**kwargs):
        attempts.append(kwargs["password"])
        if kwargs["password"] == "old":
            raise pymysql.err.OperationalError(1045, "Access denied")
        return FakeConnection([])

    db = Database(cfg, CredentialProvider(cfg, secrets_client=secrets), connect=connect)
    with db.connection():
        pass
    assert attempts == ["old", "new"]
    assert secrets.calls == 2

    # The refreshed credentials are cached for later connections.
    with db.connection():
        pass
    assert secrets.calls == 2
