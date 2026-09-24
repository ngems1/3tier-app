"""Tasks REST API (FastAPI).

Routes
  GET    /healthz              liveness (no database) - used by the ALB target group
  GET    /api/healthz          readiness (checks the database) - used by smoke tests
  GET    /api/tasks            list tasks
  POST   /api/tasks            create a task
  GET    /api/tasks/{id}       get one task
  PUT    /api/tasks/{id}       update title/description/status (partial updates allowed)
  DELETE /api/tasks/{id}       delete a task
"""

from __future__ import annotations

import logging
import time
from contextlib import asynccontextmanager
from typing import Annotated

import pymysql
from fastapi import Depends, FastAPI, HTTPException, Path, Request, status
from fastapi.responses import JSONResponse

from .config import load_settings
from .db import CredentialProvider, Database
from .models import Task, TaskCreate, TaskUpdate
from .repository import TaskRepository, TaskStore

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("tasks-api")

TaskId = Annotated[int, Path(gt=0, description="Task id")]


def get_repo(request: Request) -> TaskStore:
    return request.app.state.repository


Repo = Annotated[TaskStore, Depends(get_repo)]


def _build_repository() -> tuple[TaskRepository, str, bool]:
    settings = load_settings()
    db = Database(settings, CredentialProvider(settings))
    return TaskRepository(db), settings.app_version, settings.init_schema


def _init_schema(repo: TaskRepository, attempts: int = 10, delay: float = 3.0) -> None:
    for attempt in range(1, attempts + 1):
        try:
            repo.init_schema()
            log.info("Database schema is ready")
            return
        except pymysql.err.Error as exc:
            log.warning("Schema init attempt %d/%d failed: %s", attempt, attempts, exc)
            if attempt == attempts:
                raise
            time.sleep(delay)


def create_app(repository: TaskStore | None = None, version: str = "test") -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if repository is None:
            repo, app_version, init_schema = _build_repository()
            if init_schema:
                _init_schema(repo)
            app.state.repository = repo
            app.state.version = app_version
        else:
            app.state.repository = repository
            app.state.version = version
        log.info("Tasks API started (version %s)", app.state.version)
        yield

    app = FastAPI(title="Tasks API", lifespan=lifespan)

    @app.exception_handler(pymysql.err.Error)
    async def database_error(request: Request, exc: pymysql.err.Error) -> JSONResponse:
        log.error("Database error on %s %s: %s", request.method, request.url.path, exc)
        return JSONResponse(status_code=500, content={"detail": "database error"})

    @app.get("/healthz")
    def healthz(request: Request) -> dict:
        return {"status": "ok", "version": request.app.state.version}

    @app.get("/api/healthz")
    def readiness(request: Request, repo: Repo) -> JSONResponse:
        try:
            repo.ping()
        except pymysql.err.Error as exc:
            log.error("Readiness check failed: %s", exc)
            return JSONResponse(status_code=503, content={"status": "unavailable", "database": "down"})
        return JSONResponse({"status": "ok", "database": "up", "version": request.app.state.version})

    @app.get("/api/tasks", response_model=list[Task])
    def list_tasks(repo: Repo) -> list[Task]:
        return repo.list()

    @app.post("/api/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
    def create_task(data: TaskCreate, repo: Repo) -> Task:
        return repo.create(data)

    @app.get("/api/tasks/{task_id}", response_model=Task)
    def get_task(task_id: TaskId, repo: Repo) -> Task:
        task = repo.get(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail=f"task {task_id} not found")
        return task

    @app.put("/api/tasks/{task_id}", response_model=Task)
    def update_task(task_id: TaskId, data: TaskUpdate, repo: Repo) -> Task:
        task = repo.update(task_id, data)
        if task is None:
            raise HTTPException(status_code=404, detail=f"task {task_id} not found")
        return task

    @app.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_task(task_id: TaskId, repo: Repo) -> None:
        if not repo.delete(task_id):
            raise HTTPException(status_code=404, detail=f"task {task_id} not found")

    return app


# Uvicorn entry point: `uvicorn app.main:app`. The database is only touched
# when the app starts (lifespan), so importing this module has no side effects.
app = create_app()
