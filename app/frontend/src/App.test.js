import { render, screen } from '@testing-library/react';
import App from './App';

beforeEach(() => {
  global.fetch = jest.fn(() =>
    Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve([]) }),
  );
});

test('opens directly on the task list', async () => {
  render(<App />);
  expect(screen.getByRole('heading', { name: /tasks/i })).toBeInTheDocument();
  expect(await screen.findByText(/no tasks yet/i)).toBeInTheDocument();
  expect(global.fetch).toHaveBeenCalledWith('/api/tasks', expect.anything());
});
