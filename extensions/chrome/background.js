//
// HyperFetch Download Interceptor - Background Service Worker
// Manifest V3
//

const PRIMARY_PORT = 31415;
const FALLBACK_PORT = 31416;

const DOWNLOADABLE_EXTENSIONS = new Set([
  'zip', 'dmg', 'pkg', 'iso', 'tar', 'gz', 'tgz', '7z', 'rar',
  'mp4', 'mkv', 'avi', 'mov', 'mp3', 'wav', 'flac',
  'pdf', 'exe', 'msi', 'bin', 'app', 'xip', 'deb', 'rpm'
]);

// In-memory cache of settings
let settings = {
  enabled: true,
  interceptAll: false
};

// Initialize settings from chrome.storage
chrome.storage.local.get(['enabled', 'interceptAll'], (res) => {
  const err = chrome.runtime.lastError;
  if (err) {
    console.warn('[HyperFetch] Error reading storage settings:', err);
    return;
  }
  if (res) {
    if (res.enabled !== undefined) settings.enabled = res.enabled;
    if (res.interceptAll !== undefined) settings.interceptAll = res.interceptAll;
  }
  updateBadge();
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.enabled) settings.enabled = changes.enabled.newValue;
  if (changes.interceptAll) settings.interceptAll = changes.interceptAll.newValue;
  updateBadge();
});

function updateBadge() {
  try {
    if (settings.enabled) {
      chrome.action.setBadgeText({ text: 'ON' }, () => {
        const _ = chrome.runtime.lastError;
      });
      chrome.action.setBadgeBackgroundColor({ color: '#007AFF' }, () => {
        const _ = chrome.runtime.lastError;
      });
    } else {
      chrome.action.setBadgeText({ text: 'OFF' }, () => {
        const _ = chrome.runtime.lastError;
      });
      chrome.action.setBadgeBackgroundColor({ color: '#8E8E93' }, () => {
        const _ = chrome.runtime.lastError;
      });
    }
  } catch (e) {
    // Ignore context invalidation
  }
}

// Track recently cancelled downloads to avoid double-processing
const processedDownloadIds = new Set();

chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  if (!settings.enabled) {
    return; // Pass through to browser
  }

  if (processedDownloadIds.has(downloadItem.id)) {
    return;
  }

  const filename = downloadItem.filename || '';
  const ext = getFileExtension(filename || downloadItem.url);

  const shouldIntercept = settings.interceptAll || (ext && DOWNLOADABLE_EXTENSIONS.has(ext));

  if (!shouldIntercept) {
    return;
  }

  // Intercept the download
  processedDownloadIds.add(downloadItem.id);

  // 1. Tell Chrome to complete filename determination so state transitions cleanly
  if (typeof suggest === 'function') {
    try {
      suggest({ filename: filename || 'download' });
    } catch (e) {
      // Ignore if already suggested or closed
    }
  }

  // 2. Cancel native browser download safely, clearing any runtime.lastError
  try {
    if (!downloadItem.state || downloadItem.state === 'in_progress') {
      chrome.downloads.cancel(downloadItem.id, () => {
        const cancelError = chrome.runtime.lastError;
        if (!cancelError) {
          chrome.downloads.erase({ id: downloadItem.id }, () => {
            const eraseError = chrome.runtime.lastError;
          });
        }
        // Clean up tracking ID after 10 seconds
        setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
      });
    } else {
      setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
    }
  } catch (err) {
    setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
  }

  // Capture cookies and headers, then forward download request to HyperFetch
  (async () => {
    const cookieString = await getCookiesForUrl(downloadItem.url);
    const headers = {
      'User-Agent': navigator.userAgent,
      'Referer': downloadItem.referrer || '',
      'Accept': '*/*'
    };
    if (cookieString) {
      headers['Cookie'] = cookieString;
    }

    forwardDownloadToHyperFetch({
      url: downloadItem.url,
      filename: filename,
      referrer: downloadItem.referrer || '',
      headers: headers,
      autoStart: true
    });
  })();
});

async function getCookiesForUrl(url) {
  try {
    if (!chrome.cookies || !chrome.cookies.getAll) {
      return '';
    }
    const getCookies = (details) => new Promise((resolve) => {
      chrome.cookies.getAll(details, (cookies) => {
        const err = chrome.runtime.lastError;
        if (err || !cookies) {
          resolve([]);
        } else {
          resolve(cookies);
        }
      });
    });

    const cookies = await getCookies({ url: url });
    if (cookies && cookies.length > 0) {
      return cookies.map(c => `${c.name}=${c.value}`).join('; ');
    }

    // Fallback to domain
    const parsed = new URL(url);
    if (parsed.hostname) {
      const domainCookies = await getCookies({ domain: parsed.hostname });
      if (domainCookies && domainCookies.length > 0) {
        return domainCookies.map(c => `${c.name}=${c.value}`).join('; ');
      }
    }
  } catch (e) {
    console.warn('[HyperFetch] Could not get cookies:', e);
  }
  return '';
}

function getFileExtension(urlOrFilename) {
  try {
    const clean = urlOrFilename.split('?')[0].split('#')[0];
    const parts = clean.split('.');
    if (parts.length > 1) {
      return parts.pop().toLowerCase();
    }
  } catch (e) {}
  return '';
}

async function forwardDownloadToHyperFetch(payload) {
  // Try primary port first, then fallback port
  const ports = [PRIMARY_PORT, FALLBACK_PORT];

  for (const port of ports) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/add`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (response.ok) {
        console.log(`[HyperFetch] Successfully forwarded download to port ${port}:`, payload.filename || payload.url);
        showSuccessNotification(payload.filename || payload.url);
        return true;
      }
    } catch (err) {
      // Port unreachable or refused, try next
      console.warn(`[HyperFetch] Failed to connect on port ${port}:`, err.message);
    }
  }

  console.error('[HyperFetch] Could not reach HyperFetch app on ports', ports);
  return false;
}

function showSuccessNotification(targetName) {
  try {
    chrome.action.setBadgeText({ text: '✓' }, () => {
      const _ = chrome.runtime.lastError;
    });
    chrome.action.setBadgeBackgroundColor({ color: '#34C759' }, () => {
      const _ = chrome.runtime.lastError;
    });
    setTimeout(() => updateBadge(), 2500);
  } catch (e) {
    // Ignore context invalidation
  }
}

// Handle runtime messages from popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'checkStatus') {
    checkHyperFetchStatus().then(sendResponse).catch(() => {
      sendResponse({ connected: false });
    });
    return true; // async
  }
});

async function checkHyperFetchStatus() {
  const ports = [PRIMARY_PORT, FALLBACK_PORT];
  for (const port of ports) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/status`, { method: 'GET' });
      if (resp.ok) {
        const data = await resp.json();
        return { connected: true, port: port, version: data.version || '1.0.0' };
      }
    } catch (e) {}
  }
  return { connected: false };
}
