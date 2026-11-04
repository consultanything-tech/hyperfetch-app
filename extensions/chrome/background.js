//
// HyperFetch Download Interceptor - Background Service Worker
// Manifest V3
//

const PRIMARY_PORT = 31415;
const FALLBACK_PORT = 31416;

const DOWNLOADABLE_EXTENSIONS = new Set([
  // Archives
  'zip', 'dmg', 'pkg', 'iso', 'tar', 'gz', 'tgz', '7z', 'rar', 'bz2', 'xz', 'zst', 'lz4', 'cab', 'wim', 'jar',
  // Video
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', '3gp', 'ts',
  // Audio
  'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma',
  // Documents & Spreadsheets
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'tsv', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'epub', 'txt', 'md',
  // Data & Code
  'json', 'xml', 'yaml', 'yml', 'sql', 'sqlite', 'db', 'py', 'js', 'ts', 'html', 'css', 'sh', 'c', 'cpp', 'h', 'rs', 'go', 'swift',
  // Images
  'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'tiff', 'bmp', 'heic', 'ico', 'psd', 'ai',
  // Executables & Installers
  'exe', 'msi', 'bin', 'app', 'xip', 'deb', 'rpm', 'apk', 'ipa', 'crx', 'xpi'
]);

function isInternalOrBlobScheme(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return false;
  const lower = urlStr.trim().toLowerCase();
  return (
    lower.startsWith('blob:') ||
    lower.startsWith('data:') ||
    lower.startsWith('filesystem:') ||
    lower.startsWith('chrome:') ||
    lower.startsWith('chrome-extension:') ||
    lower.startsWith('about:') ||
    lower.startsWith('javascript:')
  );
}

function isDownloadableMime(mime) {
  if (!mime || typeof mime !== 'string') return false;
  const m = mime.toLowerCase().trim();
  if (m.startsWith('video/') || m.startsWith('audio/')) return true;
  if (m.includes('octet-stream') || m.includes('zip') || m.includes('tar') || m.includes('compressed') || m.includes('pdf')) return true;
  if (m.includes('spreadsheet') || m.includes('excel') || m.includes('word') || m.includes('presentation') || m.includes('document')) return true;
  return false;
}

// In-memory cache of settings
let settings = {
  enabled: true,
  interceptAll: false,
  bridgeToken: ''
};

// Initialize settings from chrome.storage
chrome.storage.local.get(['enabled', 'interceptAll', 'bridgeToken'], (res) => {
  const err = chrome.runtime.lastError;
  if (err) {
    console.warn('[HyperFetch] Error reading storage settings:', err);
    return;
  }
  if (res) {
    if (res.enabled !== undefined) settings.enabled = res.enabled;
    if (res.interceptAll !== undefined) settings.interceptAll = res.interceptAll;
    if (res.bridgeToken !== undefined) settings.bridgeToken = res.bridgeToken;
  }
  updateBadge();
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.enabled) settings.enabled = changes.enabled.newValue;
  if (changes.interceptAll) settings.interceptAll = changes.interceptAll.newValue;
  if (changes.bridgeToken) settings.bridgeToken = changes.bridgeToken.newValue;
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
    return; // Pass through to browser natively
  }

  const rawUrl = (downloadItem.url || '').trim();
  const finalUrl = (downloadItem.finalUrl || '').trim();
  const targetUrl = finalUrl || rawUrl;

  // Never intercept in-memory blobs, data URIs, or browser-internal schemes.
  // Web apps (ChatGPT, Claude, etc.) generate client-side downloads as in-memory
  // blobs that cannot be fetched over network by HyperFetch.
  if (isInternalOrBlobScheme(rawUrl) || isInternalOrBlobScheme(finalUrl)) {
    return; // Pass through to browser natively
  }

  if (processedDownloadIds.has(downloadItem.id)) {
    return;
  }

  const filename = downloadItem.filename || '';
  const fallbackName = getFilenameFromUrl(targetUrl) || getFilenameFromUrl(rawUrl) || 'download';
  const ext = getFileExtension(filename || targetUrl || rawUrl);

  const isExtMatch = Boolean(ext && DOWNLOADABLE_EXTENSIONS.has(ext));
  const isMimeMatch = isDownloadableMime(downloadItem.mime);
  const isLargeFile = Boolean(downloadItem.fileSize && downloadItem.fileSize > 5 * 1024 * 1024);

  const shouldIntercept = settings.interceptAll || isExtMatch || isMimeMatch || isLargeFile;

  if (!shouldIntercept) {
    return; // Pass through to browser natively
  }

  // Intercept the download asynchronously without cancelling browser download upfront.
  // In MV3, returning true allows async handling. If HyperFetch succeeds, we cancel
  // the browser download; if it fails/rejects, we call suggest() so the browser's
  // original download proceeds smoothly without interruption or restarted tokens.
  processedDownloadIds.add(downloadItem.id);

  (async () => {
    try {
      const cookieString = await getMergedCookies(targetUrl, rawUrl, downloadItem.referrer);
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
      if (success) {
        // HyperFetch accepted download: cancel and erase the native browser task
        cancelBrowserDownload(downloadItem.id);
      } else {
        console.warn('[HyperFetch] Native app unreachable or rejected, resuming browser download:', payload.url);
        showErrorBadge();
        // Resolve filename so the browser's original in-flight download continues cleanly
        try {
          suggest({ filename: filename || fallbackName });
        } catch (e) {
          // Ignore if already suggested or closed
        }
        setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
      }
    } catch (err) {
      console.error('[HyperFetch] Error during async interception:', err);
      try {
        suggest({ filename: filename || fallbackName });
      } catch (e) {}
      setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
    }
  })();

  return true; // Keep suggest callback active for async determination
});

async function getMergedCookies(url1, url2, referrer) {
  const cookieMap = new Map();
  const urls = [];
  if (url1) urls.push(url1);
  if (url2 && !urls.includes(url2)) urls.push(url2);
  if (referrer && !urls.includes(referrer)) urls.push(referrer);

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
    if (!url || typeof url !== 'string' || !url.startsWith('http')) {
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
      const headers = {
        'Content-Type': 'application/json',
        'X-HyperFetch-Client': 'extension'
      };
      if (settings.bridgeToken) {
        headers['X-HyperFetch-Token'] = settings.bridgeToken;
      }
      const response = await fetch(`http://127.0.0.1:${port}/add`, {
        method: 'POST',
        headers: headers,
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
      const headers = {
        'X-HyperFetch-Client': 'extension'
      };
      if (settings.bridgeToken) {
        headers['X-HyperFetch-Token'] = settings.bridgeToken;
      }
      const resp = await fetch(`http://127.0.0.1:${port}/status`, {
        method: 'GET',
        headers: headers
      });
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
