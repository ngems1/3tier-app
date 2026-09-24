from __future__ import annotations

from datetime import datetime

import pymysql
import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.models import Task, TaskCreate, TaskUpdate


class InMemoryTaskStore:
    """Test double implementing the same interface as TaskRepository."""

    def __init__(self) -> None:
        self.tasks: dict[int, Task] = {}
        self.next_id = 1
        self.fail = False

    def _check(self) -> None:
        if self.fail:
            raise pymysql.err.OperationalError(2003, "Can't connect to MySQL server")

    def ping(self) -> None:
        self._check()

    def list(self) -> list[Task]:
        self._check()
        return list(self.tasks.values())

    def get(self, task_id: int) -> Task | None:
        self._check()
        return self.tasks.get(task_id)

    def create(self, data: TaskCreate) -> Task:
        self._check()
        now = datetime(2026, 1, 1, 12, 0, 0)
        task = Task(id=self.next_id, created_at=now, updated_at=now, **data.model_dump())
        self.tasks[task.id] = task
        self.next_id += 1
        return task

    def update(self, task_id: int, data: TaskUpdate) -> Task | None:
        self._check()
        task = self.tasks.get(task_id)
        if task is None:
            return None
        updated = task.model_copy(update=data.model_dump(exclude_unset=True))
        self.tasks[task_id] = updated
        return updated

    def delete(self, task_id: int) -> bool:
        self._check()
        return self.tasks.pop(task_id, None) is not None


@pytest.fixture
def store() -> InMemoryTaskStore:
    return InMemoryTaskStore()


@pytest.fixture
def client(store: InMemoryTaskStore):
    with TestClient(create_app(repository=store, version="abc123")) as test_client:
        yield test_client
