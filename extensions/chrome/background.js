//
// HyperFetch Download Interceptor - Background Service Worker
// Manifest V3
//

const PRIMARY_PORT = 31415;
const FALLBACK_PORT = 31416;

const INLINE_IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'ico']);

const DOWNLOADABLE_EXTENSIONS = new Set([
  // Archives
  'zip', 'dmg', 'pkg', 'iso', 'tar', 'gz', 'tgz', '7z', 'rar', 'bz2', 'tbz2', 'xz', 'txz', 'zst', 'lz4', 'cab', 'wim', 'jar', 'war', 'ear', 'z',
  // Video
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', '3gp', 'ts', 'mts', 'm2ts', 'vob', 'ogv',
  // Audio
  'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'aiff', 'alac', 'mid', 'midi',
  // Documents
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'tsv', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'epub', 'txt', 'md', 'tex', 'pages', 'numbers', 'key',
  // Data & Code
  'json', 'xml', 'yaml', 'yml', 'sql', 'sqlite', 'db', 'sqlite3', 'parquet', 'avro', 'arrow', 'feather', 'py', 'js', 'ts', 'sh', 'c', 'cpp', 'h', 'rs', 'go', 'swift', 'java', 'kt', 'rb', 'php', 'cs',
  // Heavy / Pro Images & Design Assets
  'tiff', 'bmp', 'heic', 'heif', 'psd', 'ai', 'eps', 'raw', 'cr2', 'nef', 'dng',
  // Installers
  'exe', 'msi', 'bin', 'app', 'xip', 'deb', 'rpm', 'apk', 'aab', 'ipa'
]);

function isNetworkHttpUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return false;
  const lower = urlStr.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

function isDownloadableMime(mime) {
  if (!mime || typeof mime !== 'string') return false;
  const m = mime.toLowerCase().trim();
  if (m.startsWith('video/') || m.startsWith('audio/')) return true;
  const keywords = [
    'octet-stream', 'binary', 'zip', 'tar', 'compressed', 'pdf',
    'spreadsheet', 'excel', 'word', 'presentation', 'document',
    'csv', 'tab-separated', 'diskimage', 'apple-diskimage',
    'gzip', 'bzip', 'x-xz', '7z', 'android.package', 'iso9660',
    'msdownload', 'installer'
  ];
  return keywords.some(k => m.includes(k));
}

// In-memory cache of settings
let settings = {
  enabled: true,
  interceptAll: false,
  excludedDomains: [],
  minFileSize: 0,
  bridgeToken: ''
};

// A download event can wake a stopped worker before storage has returned the user's settings.
const settingsReady = new Promise(resolve => {
  chrome.storage.local.get(['enabled', 'interceptAll', 'excludedDomains', 'minFileSize', 'bridgeToken'], (res) => {
    const err = chrome.runtime.lastError;
    if (err) {
      console.warn('[HyperFetch] Error reading storage settings:', err);
      resolve(false);
      return;
    }
    if (res) {
      if (res.enabled !== undefined) settings.enabled = res.enabled;
      if (res.interceptAll !== undefined) settings.interceptAll = res.interceptAll;
      if (res.excludedDomains !== undefined) settings.excludedDomains = Array.isArray(res.excludedDomains) ? res.excludedDomains : [];
      if (res.minFileSize !== undefined) settings.minFileSize = Number(res.minFileSize) || 0;
      if (res.bridgeToken !== undefined) settings.bridgeToken = res.bridgeToken;
    }
    updateBadge();
    resolve(true);
  });
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.enabled) settings.enabled = changes.enabled.newValue;
  if (changes.interceptAll) settings.interceptAll = changes.interceptAll.newValue;
  if (changes.excludedDomains) settings.excludedDomains = Array.isArray(changes.excludedDomains.newValue) ? changes.excludedDomains.newValue : [];
  if (changes.minFileSize) settings.minFileSize = Number(changes.minFileSize.newValue) || 0;
  if (changes.bridgeToken) settings.bridgeToken = changes.bridgeToken.newValue;
  updateBadge();
});

function getHostname(urlStr) {
  try {
    const u = new URL(urlStr);
    return (u.hostname || '').toLowerCase();
  } catch (e) {
    return '';
  }
}

function matchesExcludedDomain(hostname, excludedDomains) {
  if (!hostname || !Array.isArray(excludedDomains) || excludedDomains.length === 0) {
    return false;
  }
  for (const rawDomain of excludedDomains) {
    const domain = (rawDomain || '').trim().toLowerCase();
    if (!domain) continue;
    if (hostname === domain || hostname.endsWith('.' + domain)) {
      return true;
    }
  }
  return false;
}

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
  const rawUrl = (downloadItem.url || '').trim();
  const targetUrl = (downloadItem.finalUrl || '').trim() || rawUrl;
  // Keep object URLs on the browser's immediate path before they can be revoked.
  if (!isNetworkHttpUrl(rawUrl) || !isNetworkHttpUrl(targetUrl)) {
    suggest();
    return;
  }
  settingsReady.then(loaded => {
    if (loaded) handleDownload(downloadItem, rawUrl, targetUrl, suggest);
    else suggest();
  });
  return true;
});

function handleDownload(downloadItem, rawUrl, targetUrl, suggest) {
  let suggested = false;
  const safeSuggest = (opts) => {
    if (suggested) return;
    suggested = true;
    try {
      if (opts) {
        suggest(opts);
      } else if (downloadItem && downloadItem.filename) {
        suggest({ filename: downloadItem.filename });
      } else {
        suggest();
      }
    } catch (e) {
      // Ignore already suggested or context closed
    }
  };

  if (!settings.enabled) {
    safeSuggest();
    return;
  }

  if (processedDownloadIds.has(downloadItem.id)) {
    safeSuggest();
    return;
  }

  // Domain exclusion check
  const hosts = [getHostname(rawUrl), getHostname(targetUrl)];
  if (hosts.some(host => matchesExcludedDomain(host, settings.excludedDomains))) {
    safeSuggest();
    return;
  }

  // Minimum file size check
  if (settings.minFileSize > 0 && downloadItem.fileSize > 0 && downloadItem.fileSize < settings.minFileSize) {
    safeSuggest();
    return;
  }

  const filename = downloadItem.filename || '';
  const fallbackName = getFilenameFromUrl(targetUrl) || getFilenameFromUrl(rawUrl) || 'download';
  const ext = getFileExtension(filename || targetUrl || rawUrl);

  // Chrome web store and Firefox extension packages should never be intercepted
  if (ext === 'crx' || ext === 'xpi') {
    safeSuggest();
    return;
  }

  // HTML pages should be saved directly by browser
  if (ext === 'html' || ext === 'htm') {
    safeSuggest();
    return;
  }

  // Exclude standard inline web images unless they are heavy assets (> 5MB)
  if (ext && INLINE_IMAGE_EXTENSIONS.has(ext)) {
    if (!downloadItem.fileSize || downloadItem.fileSize <= 5 * 1024 * 1024) {
      safeSuggest();
      return;
    }
  }

  const isExtMatch = Boolean(ext && (DOWNLOADABLE_EXTENSIONS.has(ext) || INLINE_IMAGE_EXTENSIONS.has(ext)));
  const isMimeMatch = isDownloadableMime(downloadItem.mime);
  const isLargeFile = Boolean(downloadItem.fileSize && downloadItem.fileSize > 1024 * 1024);

  const shouldIntercept = settings.interceptAll || isExtMatch || isMimeMatch || isLargeFile;

  if (!shouldIntercept) {
    safeSuggest();
    return;
  }

  // Intercept the download asynchronously without cancelling browser download upfront.
  // In MV3, returning true allows async handling. If HyperFetch succeeds, we cancel
  // the browser download; if it fails/rejects, safeSuggest() lets the browser
  // continue natively without freezing.
  processedDownloadIds.add(downloadItem.id);
  setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);

  (async () => {
    try {
      const cookieString = await getMergedCookies(targetUrl);
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
        headers: headers
      };

      const success = await forwardDownloadToHyperFetch(payload);
      if (success) {
        // HyperFetch accepted download: call safeSuggest and cancel/erase native browser task
        safeSuggest();
        cancelBrowserDownload(downloadItem.id);
        recordHandoff('accepted');
      } else {
        recordHandoff('browser');
        showErrorBadge();
        // Resolve filename so the browser's original in-flight download continues cleanly
        safeSuggest({ filename: filename || fallbackName });
      }
    } catch (err) {
      recordHandoff('browser');
      safeSuggest({ filename: filename || fallbackName });
    }
  })();

}

async function getMergedCookies(targetUrl) {
  return getCookiesForUrl(targetUrl);
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

async function tryPostDownload(port, payload) {
  try {
    const headers = {
      'Content-Type': 'application/json',
      'X-HyperFetch-Client': 'extension',
      'X-HyperFetch-Token': settings.bridgeToken || ''
    };
    const response = await fetch(`http://127.0.0.1:${port}/add`, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(1200)
    });

    if (response.ok) {
      const result = await response.json();
      if (result.status === 'ok') {
        showSuccessNotification();
        return true;
      }
    }
  } catch (err) {
    // Port unreachable or refused
  }
  return false;
}

async function checkPortStatus(port) {
  try {
    const headers = {
      'X-HyperFetch-Client': 'extension',
      'X-HyperFetch-Token': settings.bridgeToken || ''
    };
    const resp = await fetch(`http://127.0.0.1:${port}/status`, {
      method: 'GET',
      headers: headers,
      cache: 'no-store',
      signal: AbortSignal.timeout(600)
    });
    if (resp.status === 401 || resp.status === 403) return { rejected: true };
    if (resp.ok) {
      const data = await resp.json();
      if (data.app === 'HyperFetch') return { connected: true, port, version: data.version };
    }
    return { connected: false };
  } catch (e) {
    return { connected: false };
  }
}

function tryLaunchViaNativeMessaging(action = 'launch') {
  return new Promise((resolve) => {
    if (!chrome.runtime.sendNativeMessage) {
      console.warn('[HyperFetch] chrome.runtime.sendNativeMessage not available');
      resolve(false);
      return;
    }
    try {
      chrome.runtime.sendNativeMessage('com.hyperfetch.native', { action }, (response) => {
        const err = chrome.runtime.lastError;
        if (err) {
          console.warn('[HyperFetch] Native messaging launch failed:', err.message);
          resolve(false);
        } else {
          console.log('[HyperFetch] Native messaging launch succeeded:', response);
          resolve(response?.launched === true);
        }
      });
    } catch (err) {
      console.warn('[HyperFetch] sendNativeMessage error:', err);
      resolve(false);
    }
  });
}

function tryLaunchViaProtocol() {
  return new Promise((resolve) => {
    try {
      chrome.tabs.create({ url: 'hyperfetch://open', active: false }, (tab) => {
        const err = chrome.runtime.lastError;
        if (err || !tab) {
          console.warn('[HyperFetch] URL protocol launch failed:', err);
          resolve(false);
          return;
        }
        setTimeout(() => {
          if (tab.id) {
            chrome.tabs.remove(tab.id, () => {
              const _ = chrome.runtime.lastError;
            });
          }
        }, 1500);
        resolve(true);
      });
    } catch (err) {
      console.warn('[HyperFetch] Protocol launch error:', err);
      resolve(false);
    }
  });
}

function showLaunchingBadge() {
  try {
    chrome.action.setBadgeText({ text: '...' }, () => {
      const _ = chrome.runtime.lastError;
    });
    chrome.action.setBadgeBackgroundColor({ color: '#FF9500' }, () => {
      const _ = chrome.runtime.lastError;
    });
  } catch (e) {
    // Ignore context invalidation
  }
}

async function forwardDownloadToHyperFetch(payload) {
  const initial = await checkHyperFetchStatus();
  if (initial.connected) return tryPostDownload(initial.port, payload);
  if (initial.rejected) return false;

  // 2. Desktop app unreachable: attempt auto-launch
  console.log('[HyperFetch] Desktop app not responding. Attempting auto-start...');
  showLaunchingBadge();

  const launchedNative = await tryLaunchViaNativeMessaging();
  if (!launchedNative) {
    console.log('[HyperFetch] Falling back to hyperfetch:// protocol launch...');
    await tryLaunchViaProtocol();
  }

  const deadline = Date.now() + 3500;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 200));
    const status = await checkHyperFetchStatus();
    if (status.connected) return tryPostDownload(status.port, payload);
    if (status.rejected) return false;
  }

  console.error('[HyperFetch] Timed out waiting for HyperFetch to launch (3.5s elapsed).');
  return false;
}

function recordHandoff(outcome) {
  chrome.storage.session?.set({ lastHandoff: { outcome, timestamp: Date.now() } }).catch(() => {});
}

function showSuccessNotification() {
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
    settingsReady.then(checkHyperFetchStatus).then(sendResponse).catch(() => {
      sendResponse({ connected: false });
    });
    return true; // async
  }
  if (request.action === 'launchApp') {
    tryLaunchViaNativeMessaging('open').then(sendResponse);
    return true;
  }
});

async function checkHyperFetchStatus() {
  const results = await Promise.all([PRIMARY_PORT, FALLBACK_PORT].map(checkPortStatus));
  return results.find(result => result.connected) || {
    connected: false,
    rejected: results.some(result => result.rejected)
  };
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
