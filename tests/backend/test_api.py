def test_liveness_does_not_need_the_database(client, store):
    store.fail = True
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.json() == {"status": "ok", "version": "abc123"}


def test_readiness_reports_database_state(client, store):
    assert client.get("/api/healthz").json()["database"] == "up"
    store.fail = True
    res = client.get("/api/healthz")
    assert res.status_code == 503
    assert res.json()["database"] == "down"


def test_task_crud_round_trip(client):
    created = client.post("/api/tasks", json={"title": "Write runbook", "description": "rollback steps"})
    assert created.status_code == 201
    task = created.json()
    assert task["title"] == "Write runbook"
    assert task["status"] == "todo"

    assert [t["id"] for t in client.get("/api/tasks").json()] == [task["id"]]
    assert client.get(f"/api/tasks/{task['id']}").json()["description"] == "rollback steps"

    updated = client.put(f"/api/tasks/{task['id']}", json={"status": "done"})
    assert updated.status_code == 200
    assert updated.json()["status"] == "done"
    assert updated.json()["title"] == "Write runbook"

    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404
    assert client.get("/api/tasks").json() == []


def test_missing_tasks_return_404(client):
    assert client.get("/api/tasks/99").status_code == 404
    assert client.put("/api/tasks/99", json={"title": "x"}).status_code == 404
    assert client.delete("/api/tasks/99").status_code == 404


def test_invalid_input_is_rejected(client):
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422
    assert client.post("/api/tasks", json={"title": "ok", "status": "blocked"}).status_code == 422
    assert client.post("/api/tasks", json={"title": "ok", "owner": "x"}).status_code == 422
    assert client.get("/api/tasks/0").status_code == 422
    assert client.get("/api/tasks/1%20OR%201=1").status_code == 422

    task_id = client.post("/api/tasks", json={"title": "ok"}).json()["id"]
    assert client.put(f"/api/tasks/{task_id}", json={}).status_code == 422
    assert client.put(f"/api/tasks/{task_id}", json={"title": None}).status_code == 422


def test_database_errors_return_500_without_leaking_details(client, store):
    store.fail = True
    res = client.get("/api/tasks")
    assert res.status_code == 500
    assert res.json() == {"detail": "database error"}


def test_schema_init_retries_until_the_database_is_reachable():
    import pymysql

    from app.main import _init_schema

    class FlakyRepo:
        calls = 0

        def init_schema(self):
            self.calls += 1
            if self.calls < 3:
                raise pymysql.err.OperationalError(1129, "Host is blocked")

    repo = FlakyRepo()
    assert _init_schema(repo, first_delay=0, max_delay=0) is True
    assert repo.calls == 3


def test_schema_init_stops_when_the_app_shuts_down():
    import threading

    from app.main import _init_schema

    class DownRepo:
        def init_schema(self):
            raise RuntimeError("database unreachable")

    stop = threading.Event()
    stop.set()
    assert _init_schema(DownRepo(), stop=stop, first_delay=0) is False
