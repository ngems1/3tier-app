import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import Tasks from './Tasks';

const task = (overrides = {}) => ({
  id: 1,
  title: 'Write runbook',
  description: 'rollback steps',
  status: 'todo',
  created_at: '2026-01-01T12:00:00',
  updated_at: '2026-01-01T12:00:00',
  ...overrides,
});

const jsonResponse = (body, status = 200) =>
  Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    statusText: 'status',
    json: () => Promise.resolve(body),
  });

beforeEach(() => {
  global.fetch = jest.fn();
});

test('lists tasks from the API', async () => {
  global.fetch.mockReturnValueOnce(jsonResponse([task()]));
  render(<Tasks />);

  expect(await screen.findByText('Write runbook')).toBeInTheDocument();
  expect(global.fetch).toHaveBeenCalledWith('/api/tasks', expect.anything());
});

test('creates a task', async () => {
  global.fetch
    .mockReturnValueOnce(jsonResponse([]))
    .mockReturnValueOnce(jsonResponse(task({ id: 2, title: 'Add alarms', description: null }), 201));
  render(<Tasks />);
  await screen.findByText('No tasks yet.');

  fireEvent.change(screen.getByLabelText('New task title'), { target: { value: 'Add alarms' } });
  fireEvent.click(screen.getByRole('button', { name: 'Add task' }));

  expect(await screen.findByText('Add alarms')).toBeInTheDocument();
  const [url, options] = global.fetch.mock.calls[1];
  expect(url).toBe('/api/tasks');
  expect(options.method).toBe('POST');
  expect(JSON.parse(options.body)).toEqual({ title: 'Add alarms', description: null });
});

test('updates the status of a task', async () => {
  global.fetch
    .mockReturnValueOnce(jsonResponse([task()]))
    .mockReturnValueOnce(jsonResponse(task({ status: 'done' })));
  render(<Tasks />);
  const select = await screen.findByLabelText('Status for task 1');

  fireEvent.change(select, { target: { value: 'done' } });

  await waitFor(() => expect(screen.getByLabelText('Status for task 1')).toHaveValue('done'));
  const [url, options] = global.fetch.mock.calls[1];
  expect(url).toBe('/api/tasks/1');
  expect(options.method).toBe('PUT');
  expect(JSON.parse(options.body)).toEqual({ status: 'done' });
});

test('deletes a task', async () => {
  global.fetch
    .mockReturnValueOnce(jsonResponse([task()]))
    .mockReturnValueOnce(Promise.resolve({ ok: true, status: 204, statusText: 'No Content' }));
  render(<Tasks />);
  const row = (await screen.findByText('Write runbook')).closest('tr');

  fireEvent.click(within(row).getByRole('button', { name: 'Delete' }));

  expect(await screen.findByText('No tasks yet.')).toBeInTheDocument();
  expect(global.fetch.mock.calls[1][1].method).toBe('DELETE');
});

test('shows API errors to the user', async () => {
  global.fetch.mockReturnValueOnce(jsonResponse({ detail: 'database error' }, 500));
  render(<Tasks />);

  expect(await screen.findByRole('alert')).toHaveTextContent('database error');
});
