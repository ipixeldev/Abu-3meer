(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.AbuPwaLifecycle = api;

  if (root.document) {
    const start = function () { api.create(root).start(); };
    if (root.document.readyState === 'loading') {
      root.document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
      start();
    }
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const DISMISS_KEY = 'abu3meer:pwa-install-dismissed-until';
  const RELOAD_KEY = 'abu3meer:pwa-update-reloaded-at';
  const DISMISS_DURATION_MS = 7 * 24 * 60 * 60 * 1000;
  const RELOAD_GUARD_MS = 15000;

  function safeRead(storage, key) {
    try { return storage && storage.getItem(key); } catch (_) { return null; }
  }

  function safeWrite(storage, key, value) {
    try { if (storage) storage.setItem(key, value); } catch (_) { /* Private mode. */ }
  }

  function safeRemove(storage, key) {
    try { if (storage) storage.removeItem(key); } catch (_) { /* Private mode. */ }
  }

  function create(windowRef) {
    const documentRef = windowRef.document;
    const navigatorRef = windowRef.navigator || {};
    const panel = documentRef.getElementById('pwa-promotion');
    const title = documentRef.getElementById('pwa-promotion-title');
    const message = documentRef.getElementById('pwa-promotion-message');
    const action = documentRef.getElementById('pwa-promotion-action');
    const dismiss = documentRef.getElementById('pwa-promotion-dismiss');
    let localStorageRef = null;
    let sessionStorageRef = null;
    try { localStorageRef = windowRef.localStorage; } catch (_) { /* Restricted storage. */ }
    try { sessionStorageRef = windowRef.sessionStorage; } catch (_) { /* Restricted storage. */ }
    let deferredInstallPrompt = null;
    let waitingWorker = null;
    let mode = 'hidden';
    let activationRequested = false;
    const languages = Array.isArray(navigatorRef.languages)
      ? navigatorRef.languages
      : [navigatorRef.language || ''];
    const isArabic = languages.some((value) => String(value).toLowerCase().startsWith('ar'));
    const copy = isArabic
      ? {
          installTitle: 'ثبّت أبو 3مير',
          installMessage: 'أضف تجربة المشجعين إلى هذا الجهاز.',
          installAction: 'تثبيت',
          updateTitle: 'تحديث جديد جاهز',
          updateMessage: 'أعد التحميل مرة واحدة لاستخدام أحدث إصدار.',
          updateAction: 'تحديث',
        }
      : {
          installTitle: 'INSTALL ABU 3MEER',
          installMessage: 'Add the fan experience to this device.',
          installAction: 'INSTALL',
          updateTitle: 'UPDATE READY',
          updateMessage: 'Reload once to use the latest Abu 3meer release.',
          updateAction: 'UPDATE',
        };

    function isStandalone() {
      const displayMode = typeof windowRef.matchMedia === 'function' &&
        windowRef.matchMedia('(display-mode: standalone)').matches;
      return displayMode || navigatorRef.standalone === true;
    }

    function installPromotionIsSuppressed() {
      const until = Number(safeRead(localStorageRef, DISMISS_KEY) || 0);
      return Number.isFinite(until) && until > Date.now();
    }

    function hide() {
      mode = 'hidden';
      if (panel) panel.hidden = true;
    }

    function show(nextMode) {
      if (!panel || !title || !message || !action) return;
      mode = nextMode;
      action.disabled = false;
      panel.dataset.mode = nextMode;
      panel.hidden = false;
      panel.dir = isArabic ? 'rtl' : 'ltr';
      if (nextMode === 'update') {
        title.textContent = copy.updateTitle;
        message.textContent = copy.updateMessage;
        action.textContent = copy.updateAction;
      } else {
        title.textContent = copy.installTitle;
        message.textContent = copy.installMessage;
        action.textContent = copy.installAction;
      }
    }

    function onBeforeInstallPrompt(event) {
      if (isStandalone() || installPromotionIsSuppressed()) return;
      // A custom button is only created when the browser confirms that this
      // device is installable. Calling preventDefault here keeps that one-time
      // event for the explicit user gesture below.
      event.preventDefault();
      deferredInstallPrompt = event;
      if (mode !== 'update') show('install');
    }

    async function runPrimaryAction() {
      if (mode === 'update') {
        if (!waitingWorker) return;
        activationRequested = true;
        if (action) action.disabled = true;
        waitingWorker.postMessage({ type: 'SKIP_WAITING' });
        return;
      }
      const promptEvent = deferredInstallPrompt;
      if (!promptEvent) return hide();
      hide();
      deferredInstallPrompt = null;
      try {
        await promptEvent.prompt();
        const choice = await promptEvent.userChoice;
        if (!choice || choice.outcome !== 'accepted') {
          safeWrite(
            localStorageRef,
            DISMISS_KEY,
            String(Date.now() + DISMISS_DURATION_MS),
          );
        }
      } catch (_) {
        // The browser can invalidate the event if installability changes.
      }
    }

    function dismissPromotion() {
      if (mode === 'install') {
        safeWrite(
          localStorageRef,
          DISMISS_KEY,
          String(Date.now() + DISMISS_DURATION_MS),
        );
        deferredInstallPrompt = null;
      }
      hide();
    }

    function watchRegistration(registration) {
      function offerUpdate(worker) {
        if (!worker || !navigatorRef.serviceWorker.controller) return;
        waitingWorker = worker;
        show('update');
      }

      offerUpdate(registration.waiting);
      registration.addEventListener('updatefound', function () {
        const installing = registration.installing;
        if (!installing) return;
        installing.addEventListener('statechange', function () {
          if (installing.state === 'installed') offerUpdate(registration.waiting || installing);
        });
      });

      registration.update().catch(function (error) {
        console.info('PWA update check skipped:', error);
      });
    }

    function registerServiceWorker() {
      const serviceWorker = navigatorRef.serviceWorker;
      const localHost = windowRef.location.hostname === 'localhost' ||
        windowRef.location.hostname === '127.0.0.1';
      if (!serviceWorker || (windowRef.location.protocol !== 'https:' && !localHost)) {
        return Promise.resolve(null);
      }
      serviceWorker.addEventListener('controllerchange', function () {
        if (!activationRequested) return;
        const lastReload = Number(safeRead(sessionStorageRef, RELOAD_KEY) || 0);
        if (Number.isFinite(lastReload) && Date.now() - lastReload < RELOAD_GUARD_MS) {
          activationRequested = false;
          hide();
          return;
        }
        safeWrite(sessionStorageRef, RELOAD_KEY, String(Date.now()));
        windowRef.location.reload();
      });
      return serviceWorker.register('/pwa_service_worker.js', { scope: '/' })
        .then(function (registration) {
          watchRegistration(registration);
          return registration;
        })
        .catch(function (error) {
          console.info('PWA service worker unavailable:', error);
          return null;
        });
    }

    function start() {
      if (panel) panel.hidden = true;
      if (action) action.addEventListener('click', runPrimaryAction);
      if (dismiss) dismiss.addEventListener('click', dismissPromotion);
      windowRef.addEventListener('beforeinstallprompt', onBeforeInstallPrompt);
      windowRef.addEventListener('appinstalled', function () {
        safeRemove(localStorageRef, DISMISS_KEY);
        deferredInstallPrompt = null;
        hide();
      });
      if (isStandalone()) documentRef.body.classList.add('pwa-standalone');
      return registerServiceWorker();
    }

    return {
      start: start,
      isStandalone: isStandalone,
      getMode: function () { return mode; },
    };
  }

  return {
    create: create,
    constants: {
      dismissKey: DISMISS_KEY,
      reloadKey: RELOAD_KEY,
      dismissDurationMs: DISMISS_DURATION_MS,
    },
  };
}));
