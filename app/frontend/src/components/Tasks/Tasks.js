import React, { useCallback, useEffect, useState } from 'react';
import { createTask, deleteTask, listTasks, updateTask } from '../../api';
import './Tasks.css';

const STATUSES = [
  { value: 'todo', label: 'To do' },
  { value: 'in_progress', label: 'In progress' },
  { value: 'done', label: 'Done' },
];

function TaskRow({ task, onUpdate, onDelete }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description || '');

  const save = async (event) => {
    event.preventDefault();
    const ok = await onUpdate(task.id, { title: title.trim(), description: description.trim() || null });
    if (ok) {
      setEditing(false);
    }
  };

  const cancel = () => {
    setTitle(task.title);
    setDescription(task.description || '');
    setEditing(false);
  };

  return (
    <tr>
      <td>{task.id}</td>
      {editing ? (
        <td colSpan={2}>
          <form className="task-edit" onSubmit={save}>
            <input
              aria-label={`Title for task ${task.id}`}
              value={title}
              maxLength={200}
              required
              onChange={(e) => setTitle(e.target.value)}
            />
            <input
              aria-label={`Description for task ${task.id}`}
              value={description}
              maxLength={1000}
              onChange={(e) => setDescription(e.target.value)}
            />
            <button type="submit" disabled={!title.trim()}>Save</button>
            <button type="button" onClick={cancel}>Cancel</button>
          </form>
        </td>
      ) : (
        <>
          <td>{task.title}</td>
          <td>{task.description}</td>
        </>
      )}
      <td>
        <select
          aria-label={`Status for task ${task.id}`}
          value={task.status}
          onChange={(e) => onUpdate(task.id, { status: e.target.value })}
        >
          {STATUSES.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
      </td>
      <td className="task-actions">
        {!editing && (
          <button type="button" onClick={() => setEditing(true)}>Edit</button>
        )}
        <button type="button" onClick={() => onDelete(task.id)}>Delete</button>
      </td>
    </tr>
  );
}

function Tasks() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');

  const run = useCallback(async (action) => {
    try {
      setError('');
      await action();
      return true;
    } catch (e) {
      setError(e.message);
      return false;
    }
  }, []);

  const refresh = useCallback(
    () => run(async () => setTasks(await listTasks())),
    [run],
  );

  useEffect(() => {
    refresh().finally(() => setLoading(false));
  }, [refresh]);

  const handleCreate = async (event) => {
    event.preventDefault();
    const ok = await run(async () => {
      const task = await createTask({ title: title.trim(), description: description.trim() || null });
      setTasks((current) => [...current, task]);
    });
    if (ok) {
      setTitle('');
      setDescription('');
    }
  };

  const handleUpdate = (id, changes) =>
    run(async () => {
      const updated = await updateTask(id, changes);
      setTasks((current) => current.map((t) => (t.id === id ? updated : t)));
    });

  const handleDelete = (id) =>
    run(async () => {
      await deleteTask(id);
      setTasks((current) => current.filter((t) => t.id !== id));
    });

  return (
    <div className="tasks">
      <h1>Tasks</h1>

      <form className="task-create" onSubmit={handleCreate}>
        <input
          aria-label="New task title"
          placeholder="Title"
          value={title}
          maxLength={200}
          onChange={(e) => setTitle(e.target.value)}
        />
        <input
          aria-label="New task description"
          placeholder="Description (optional)"
          value={description}
          maxLength={1000}
          onChange={(e) => setDescription(e.target.value)}
        />
        <button type="submit" disabled={!title.trim()}>Add task</button>
      </form>

      {error && <p role="alert" className="task-error">{error}</p>}

      {loading ? (
        <p>Loading…</p>
      ) : tasks.length === 0 ? (
        <p>No tasks yet.</p>
      ) : (
        <table className="task-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Title</th>
              <th>Description</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {tasks.map((task) => (
              <TaskRow key={task.id} task={task} onUpdate={handleUpdate} onDelete={handleDelete} />
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

export default Tasks;
