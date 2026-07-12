import http from 'k6/http';
import { sleep, check } from 'k6';

// Porta passada por variável de ambiente
const PORT = __ENV.PORT;
const BASE_URL = `http://host.docker.internal:${PORT}`;

export const options = {
  stages: [
    { duration: '30s', target: 10 }, // ramp-up / JIT warm-up, excluded mentally from steady-state read
    { duration: '5m', target: 10 },  // sustained load - this is the window to read CPU/memory from
    { duration: '15s', target: 0 },  // ramp-down
  ],
};

export default function () {
  // 30% CRIAÇÃO (POST), 70% LEITURA (GET)
  if (Math.random() < 0.3) {
    const payload = JSON.stringify({
      title: `Book ${Math.random()}`,
      author: 'Load Test',
      price : Math.floor(Math.random() * 100) + 1,
    });

    const params = {
      headers: { 'Content-Type': 'application/json' },
    };

    const res = http.post(`${BASE_URL}/books`, payload, params);

    check(res, {
      'POST status is 201': (r) => r.status === 201 || r.status === 200,
    });
  } else {
    const res = http.get(`${BASE_URL}/books/1`);

    check(res, {
      'GET status is 200': (r) => r.status === 200,
    });
  }

  sleep(0.1);
}
