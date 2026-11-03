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

function cancelBrowserDownload(downloadId) {
  try {
    chrome.downloads.cancel(downloadId, () => {
      const _ = chrome.runtime.lastError;
      chrome.downloads.erase({ id: downloadId }, () => {
        const _ = chrome.runtime.lastError;
      });
      setTimeout(() => processedDownloadIds.delete(downloadId), 10000);
    });
  } catch (e) {
    setTimeout(() => processedDownloadIds.delete(downloadId), 10000);
  }
}

chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  if (!settings.enabled) {
    return; // Pass through to browser
  }

  if (processedDownloadIds.has(downloadItem.id)) {
    return;
  }

  const targetUrl = downloadItem.finalUrl || downloadItem.url;
  const filename = downloadItem.filename || '';
  const fallbackName = getFilenameFromUrl(targetUrl) || getFilenameFromUrl(downloadItem.url) || 'download';
  const ext = getFileExtension(filename || targetUrl || downloadItem.url);

  const shouldIntercept = settings.interceptAll || (ext && DOWNLOADABLE_EXTENSIONS.has(ext));

  if (!shouldIntercept) {
    return;
  }

  // Intercept the download
  processedDownloadIds.add(downloadItem.id);

  // 1. Tell Chrome to complete filename determination so state transitions cleanly
  if (typeof suggest === 'function') {
    try {
      suggest({ filename: filename || fallbackName });
    } catch (e) {
      // Ignore if already suggested or closed
    }
  }

  // 2. Cancel native browser download safely, clearing any runtime.lastError
  cancelBrowserDownload(downloadItem.id);

  // Capture cookies and headers, then forward download request to HyperFetch
  (async () => {
    const cookieString = await getMergedCookies(targetUrl, downloadItem.url);
    const headers = {
      'User-Agent': navigator.userAgent,
      'Referer': downloadItem.referrer || '',
      'Accept': '*/*',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'cross-site'
    };
    if (cookieString) {
      headers['Cookie'] = cookieString;
    }

    const payload = {
      url: targetUrl,
      filename: filename || fallbackName,
      referrer: downloadItem.referrer || '',
      headers: headers,
      autoStart: true
    };

    const success = await forwardDownloadToHyperFetch(payload);
    if (!success) {
      console.warn('[HyperFetch] Native app unreachable, falling back to browser download for:', payload.url);
      showErrorBadge();
      try {
        chrome.downloads.download({
          url: payload.url,
          filename: payload.filename || undefined,
          saveAs: false
        }, (downloadId) => {
          const _ = chrome.runtime.lastError;
          if (downloadId) {
            processedDownloadIds.add(downloadId);
          }
        });
      } catch (fallbackErr) {
        console.error('[HyperFetch] Failed to re-trigger fallback download:', fallbackErr);
      }
    }
  })();
});

async function getMergedCookies(url1, url2) {
  const cookieMap = new Map();
  const urls = [url1];
  if (url2 && url2 !== url1) {
    urls.push(url2);
  }

  for (const target of urls) {
    if (!target) continue;
    const cookieStr = await getCookiesForUrl(target);
    if (cookieStr) {
      const parts = cookieStr.split('; ');
      for (const part of parts) {
        const eqIdx = part.indexOf('=');
        if (eqIdx !== -1) {
          const name = part.substring(0, eqIdx).trim();
          const val = part.substring(eqIdx + 1).trim();
          if (name && !cookieMap.has(name)) {
            cookieMap.set(name, val);
          }
        }
      }
    }
  }

  if (cookieMap.size === 0) return '';
  return Array.from(cookieMap.entries()).map(([k, v]) => `${k}=${v}`).join('; ');
}

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

function showErrorBadge() {
  try {
    chrome.action.setBadgeText({ text: '!' }, () => {
      const _ = chrome.runtime.lastError;
    });
    chrome.action.setBadgeBackgroundColor({ color: '#FF3B30' }, () => {
      const _ = chrome.runtime.lastError;
    });
    setTimeout(() => updateBadge(), 4000);
  } catch (e) {}
}

function getFilenameFromUrl(url) {
  try {
    const pathname = new URL(url).pathname;
    const lastSegment = pathname.substring(pathname.lastIndexOf('/') + 1);
    return decodeURIComponent(lastSegment.split('?')[0]);
  } catch (e) {
    return '';
  }
}
