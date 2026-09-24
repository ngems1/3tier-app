// Thin client for the Tasks API. The web tier (Nginx) proxies /api/* to the
// backend, so relative URLs work locally, in Docker Compose and on AWS.

const BASE = '/api/tasks';

async function request(url, options = {}) {
  const response = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!response.ok) {
    let detail = `${response.status} ${response.statusText}`;
    try {
      const body = await response.json();
      if (body && body.detail) {
        detail = typeof body.detail === 'string' ? body.detail : JSON.stringify(body.detail);
      }
    } catch (e) {
      // response had no JSON body; keep the status text
    }
    throw new Error(detail);
  }
  return response.status === 204 ? null : response.json();
}

export const listTasks = () => request(BASE);

export const createTask = (task) =>
  request(BASE, { method: 'POST', body: JSON.stringify(task) });

export const updateTask = (id, changes) =>
  request(`${BASE}/${id}`, { method: 'PUT', body: JSON.stringify(changes) });

export const deleteTask = (id) => request(`${BASE}/${id}`, { method: 'DELETE' });
