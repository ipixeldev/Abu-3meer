'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const lifecycle = require('../web/pwa_lifecycle.js');

class FakeTarget {
  constructor() { this.listeners = new Map(); }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  async dispatch(type, event = {}) {
    const results = (this.listeners.get(type) || []).map((listener) => listener(event));
    await Promise.all(results);
  }
}

class FakeElement extends FakeTarget {
  constructor() {
    super();
    this.hidden = true;
    this.dataset = {};
    this.textContent = '';
    this.disabled = false;
  }
}

class FakeStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, value); }
  removeItem(key) { this.values.delete(key); }
}

function createEnvironment({ standalone = false, waiting = null, controlled = false, language = 'en' } = {}) {
  const ids = [
    'pwa-promotion',
    'pwa-promotion-title',
    'pwa-promotion-message',
    'pwa-promotion-action',
    'pwa-promotion-dismiss',
  ];
  const elements = Object.fromEntries(ids.map((id) => [id, new FakeElement()]));
  const bodyClasses = new Set();
  const registration = new FakeTarget();
  registration.waiting = waiting;
  registration.installing = null;
  registration.update = async () => undefined;
  const serviceWorker = new FakeTarget();
  serviceWorker.controller = controlled ? {} : null;
  serviceWorker.register = async () => registration;
  const windowRef = new FakeTarget();
  let reloads = 0;
  windowRef.document = {
    getElementById: (id) => elements[id] || null,
    body: { classList: { add: (value) => bodyClasses.add(value) } },
  };
  windowRef.navigator = { serviceWorker, standalone: false, language, languages: [language] };
  windowRef.location = {
    protocol: 'https:',
    hostname: 'abu-3meer.web.app',
    reload: () => { reloads += 1; },
  };
  windowRef.localStorage = new FakeStorage();
  windowRef.sessionStorage = new FakeStorage();
  windowRef.matchMedia = () => ({ matches: standalone });
  windowRef.getReloads = () => reloads;
  return { windowRef, elements, bodyClasses, serviceWorker, registration };
}

test('install promotion appears only after browser eligibility and remembers dismissal', async () => {
  const env = createEnvironment();
  const controller = lifecycle.create(env.windowRef);
  await controller.start();
  assert.equal(controller.getMode(), 'hidden');

  let prevented = false;
  const prompt = {
    preventDefault: () => { prevented = true; },
    prompt: async () => undefined,
    userChoice: Promise.resolve({ outcome: 'dismissed' }),
  };
  await env.windowRef.dispatch('beforeinstallprompt', prompt);
  assert.equal(prevented, true);
  assert.equal(controller.getMode(), 'install');
  assert.equal(env.elements['pwa-promotion'].hidden, false);

  await env.elements['pwa-promotion-dismiss'].dispatch('click');
  assert.equal(controller.getMode(), 'hidden');
  assert.ok(Number(env.windowRef.localStorage.getItem(lifecycle.constants.dismissKey)) > Date.now());

  prevented = false;
  await env.windowRef.dispatch('beforeinstallprompt', prompt);
  assert.equal(prevented, false);
  assert.equal(controller.getMode(), 'hidden');
});

test('a waiting worker reloads once only after the user accepts the update', async () => {
  const waitingWorker = { messages: [], postMessage(message) { this.messages.push(message); } };
  const env = createEnvironment({ waiting: waitingWorker, controlled: true });
  const controller = lifecycle.create(env.windowRef);
  await controller.start();

  assert.equal(controller.getMode(), 'update');
  assert.equal(env.windowRef.getReloads(), 0);
  await env.elements['pwa-promotion-action'].dispatch('click');
  assert.deepEqual(waitingWorker.messages, [{ type: 'SKIP_WAITING' }]);
  await env.serviceWorker.dispatch('controllerchange');
  assert.equal(env.windowRef.getReloads(), 1);
  await env.serviceWorker.dispatch('controllerchange');
  assert.equal(env.windowRef.getReloads(), 1);
});

test('standalone mode never exposes an install promotion', async () => {
  const env = createEnvironment({ standalone: true });
  const controller = lifecycle.create(env.windowRef);
  await controller.start();
  let prevented = false;
  await env.windowRef.dispatch('beforeinstallprompt', {
    preventDefault: () => { prevented = true; },
  });

  assert.equal(prevented, false);
  assert.equal(controller.getMode(), 'hidden');
  assert.equal(env.bodyClasses.has('pwa-standalone'), true);
});

test('the browser-level install surface is localized for Arabic devices', async () => {
  const env = createEnvironment({ language: 'ar-SA' });
  const controller = lifecycle.create(env.windowRef);
  await controller.start();
  await env.windowRef.dispatch('beforeinstallprompt', {
    preventDefault: () => undefined,
  });

  assert.match(env.elements['pwa-promotion-title'].textContent, /أبو 3مير/);
  assert.equal(env.elements['pwa-promotion-action'].textContent, 'تثبيت');
  assert.equal(env.elements['pwa-promotion'].dir, 'rtl');
});

test('manifest and offline shell use the same brand and required install assets', () => {
  const repoRoot = path.resolve(__dirname, '..');
  const manifest = JSON.parse(fs.readFileSync(path.join(repoRoot, 'web/manifest.json'), 'utf8'));
  const worker = fs.readFileSync(path.join(repoRoot, 'web/pwa_service_worker.js'), 'utf8');

  assert.equal(manifest.name, 'Abu 3meer');
  assert.equal(manifest.background_color, manifest.theme_color);
  assert.ok(manifest.icons.some((icon) => icon.sizes === '512x512' && icon.purpose === 'maskable'));
  assert.match(worker, /'\/main\.dart\.js'/);
  assert.match(worker, /type === 'SKIP_WAITING'/);
  assert.match(worker, /name\.startsWith\('abu3meer-pwa-'\)/);
});
