import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import { supportRoutes, whatsappSupportUrl } from '../routes/supportRoutes.js';

test('WhatsApp contact accepts only international digits, never URLs or placeholders', () => {
  assert.equal(whatsappSupportUrl(' 46701234567 '), 'https://wa.me/46701234567');
  for (const invalid of ['', '+46701234567', '0046701234567', 'number_later',
    '4670 1234567', 'https://evil.example', '46701234567?text=secret',
    '12345', '1234567890123456']) {
    assert.equal(whatsappSupportUrl(invalid), null);
  }
});

test('public support endpoint exposes only a validated contact URL and never config secrets', async () => {
  const app = Fastify();
  let number = '';
  await supportRoutes(app, { number: () => number });
  try {
    const empty = await app.inject('/support/contact');
    assert.equal(empty.statusCode, 200);
    assert.deepEqual(empty.json(), { data: { whatsappUrl: null } });
    assert.equal(empty.headers['cache-control'], 'no-store');
    number = '46701234567';
    const configured = await app.inject('/support/contact');
    assert.deepEqual(configured.json(), { data: { whatsappUrl: 'https://wa.me/46701234567' } });
    number = 'sk_private';
    assert.deepEqual((await app.inject('/support/contact')).json(), { data: { whatsappUrl: null } });
  } finally { await app.close(); }
});
