"""Data access for tasks. Every query is parameterized; user input never
becomes part of the SQL text."""

from __future__ import annotations

from typing import Protocol

from .db import Database
from .models import Task, TaskCreate, TaskUpdate

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    title       VARCHAR(200) NOT NULL,
    description VARCHAR(1000) NULL,
    status      ENUM('todo', 'in_progress', 'done') NOT NULL DEFAULT 'todo',
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
"""

COLUMNS = "id, title, description, status, created_at, updated_at"

# Only these column names can appear in an UPDATE; values are always bound.
UPDATABLE_COLUMNS = ("title", "description", "status")


class TaskStore(Protocol):
    def ping(self) -> None: ...
    def list(self) -> list[Task]: ...
    def get(self, task_id: int) -> Task | None: ...
    def create(self, data: TaskCreate) -> Task: ...
    def update(self, task_id: int, data: TaskUpdate) -> Task | None: ...
    def delete(self, task_id: int) -> bool: ...


class TaskRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def init_schema(self) -> None:
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute(SCHEMA)

    def ping(self) -> None:
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")

    def list(self) -> list[Task]:
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute(f"SELECT {COLUMNS} FROM tasks ORDER BY id")
            return [Task(**row) for row in cur.fetchall()]

    def get(self, task_id: int) -> Task | None:
        with self._db.connection() as conn, conn.cursor() as cur:
            return self._get(cur, task_id)

    def create(self, data: TaskCreate) -> Task:
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO tasks (title, description, status) VALUES (%s, %s, %s)",
                (data.title, data.description, data.status.value),
            )
            return self._get(cur, cur.lastrowid)

    def update(self, task_id: int, data: TaskUpdate) -> Task | None:
        changes = data.model_dump(exclude_unset=True, mode="json")
        columns = [c for c in UPDATABLE_COLUMNS if c in changes]
        assignments = ", ".join(f"{c} = %s" for c in columns)
        params = [changes[c] for c in columns] + [task_id]
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute(f"UPDATE tasks SET {assignments} WHERE id = %s", params)
            return self._get(cur, task_id)

    def delete(self, task_id: int) -> bool:
        with self._db.connection() as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
            return cur.rowcount > 0

    @staticmethod
    def _get(cur, task_id: int) -> Task | None:
        cur.execute(f"SELECT {COLUMNS} FROM tasks WHERE id = %s", (task_id,))
        row = cur.fetchone()
        return Task(**row) if row else None
