// Reads claude.ai cookies via the WebExtensions cookies API, joins them into
// a single Cookie header value, URL-encodes it, and hands off to the
// TokenTrace macOS app via the `tokentrace://import?cookie=…` URL scheme.
//
// The cookie value is never displayed, persisted, or sent anywhere other
// than the host application's URL scheme handler.

const statusEl = document.getElementById('status');
const sendBtn = document.getElementById('send');
const hintEl = document.getElementById('hint');

function showError(message, detail) {
  statusEl.textContent = message;
  statusEl.classList.add('error');
  if (detail) hintEl.textContent = detail;
}

function showInfo(message, detail) {
  statusEl.textContent = message;
  statusEl.classList.remove('error');
  if (detail !== undefined) hintEl.textContent = detail;
}

async function handoff(cookieHeader) {
  const url = `tokentrace://import?cookie=${encodeURIComponent(cookieHeader)}`;
  // tabs.create is the most reliable way to invoke a custom URL scheme
  // across Firefox / Zen / LibreWolf. The opened tab closes itself once the
  // OS has dispatched the URL to the registered handler.
  await browser.tabs.create({ url, active: false });
}

(async () => {
  try {
    const cookies = await browser.cookies.getAll({ domain: 'claude.ai' });
    if (!cookies || cookies.length === 0) {
      showInfo('No claude.ai cookies found.',
        'Sign in to claude.ai first, then click this icon again.');
      return;
    }
    if (!cookies.some(c => c.name === 'sessionKey')) {
      showInfo('Not signed in.',
        'No sessionKey cookie. Sign in to claude.ai, then click this icon again.');
      return;
    }
    const header = cookies.map(c => `${c.name}=${c.value}`).join('; ');
    showInfo(`Found ${cookies.length} cookies (incl. sessionKey).`,
      'Click below to send. TokenTrace will ask you to confirm.');
    sendBtn.disabled = false;
    sendBtn.addEventListener('click', async () => {
      sendBtn.disabled = true;
      try {
        await handoff(header);
        showInfo('Sent to TokenTrace.',
          'Confirm the import in the TokenTrace Settings tab.');
        setTimeout(() => window.close(), 900);
      } catch (e) {
        showError('Could not open tokentrace://', String(e));
        sendBtn.disabled = false;
      }
    });
  } catch (e) {
    showError('Cookie read failed.', String(e));
  }
})();
