//
// HyperFetch Popup Script
//

document.addEventListener('DOMContentLoaded', () => {
  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const interceptToggle = document.getElementById('interceptToggle');
  const scopeFiltered = document.getElementById('scopeFiltered');
  const scopeAll = document.getElementById('scopeAll');
  const openAppBtn = document.getElementById('openAppBtn');
  const retryBtn = document.getElementById('retryBtn');
  const minSizeSelect = document.getElementById('minSizeSelect');
  const excludedDomainsInput = document.getElementById('excludedDomainsInput');
  const bridgeTokenInput = document.getElementById('bridgeTokenInput');
  const transfersCountBadge = document.getElementById('transfersCountBadge');
  const transfersList = document.getElementById('transfersList');
  const footerStatusText = document.getElementById('footerStatusText');
  const handoffStatus = document.getElementById('handoffStatus');

  let connectedPort = null;
  let pollTimeoutId = null;
  let consecutiveErrors = 0;
  let currentBridgeToken = '';
  let connectionCheck = 0;

  // Load saved preferences
  chrome.storage.local.get([
    'enabled',
    'interceptAll',
    'minFileSize',
    'excludedDomains',
    'bridgeToken'
  ], (res) => {
    if (chrome.runtime.lastError) {
      setOffline();
      return;
    }
    if (res) {
      if (res.enabled !== undefined && interceptToggle) {
        interceptToggle.checked = res.enabled;
      }
      if (res.interceptAll) {
        if (scopeAll) scopeAll.checked = true;
      } else {
        if (scopeFiltered) scopeFiltered.checked = true;
      }

      if (res.minFileSize !== undefined && minSizeSelect) {
        minSizeSelect.value = String(res.minFileSize);
      }

      if (res.excludedDomains !== undefined && excludedDomainsInput) {
        const domains = Array.isArray(res.excludedDomains) ? res.excludedDomains : [];
        excludedDomainsInput.value = domains.join('\n');
      }

      if (res.bridgeToken !== undefined && bridgeTokenInput) {
        bridgeTokenInput.value = res.bridgeToken;
        currentBridgeToken = res.bridgeToken || '';
      }
    }
    checkConnection();
  });

  // Handle toggle change
  interceptToggle?.addEventListener('change', () => {
    const isEnabled = interceptToggle.checked;
    chrome.storage.local.set({ enabled: isEnabled });
  });

  // Handle scope change
  scopeFiltered?.addEventListener('change', () => {
    if (scopeFiltered.checked) {
      chrome.storage.local.set({ interceptAll: false });
    }
  });

  scopeAll?.addEventListener('change', () => {
    if (scopeAll.checked) {
      chrome.storage.local.set({ interceptAll: true });
    }
  });

  // Handle min file size change
  if (minSizeSelect) {
    minSizeSelect.addEventListener('change', () => {
      const minSize = parseInt(minSizeSelect.value, 10) || 0;
      chrome.storage.local.set({ minFileSize: minSize });
    });
  }

  // Handle excluded domains change
  if (excludedDomainsInput) {
    const saveDomains = () => {
      const raw = excludedDomainsInput.value || '';
      const domains = [...new Set(raw
        .split(/[\n,]+/)
        .map(d => d.trim().toLowerCase())
        .filter(Boolean))];
      const hostname = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
      const invalid = domains.some(domain => !hostname.test(domain));
      excludedDomainsInput.setCustomValidity(invalid ? 'Enter hostnames without a URL scheme, path, or wildcard.' : '');
      if (invalid) {
        excludedDomainsInput.reportValidity();
        return;
      }
      chrome.storage.local.set({ excludedDomains: domains });
    };
    excludedDomainsInput.addEventListener('change', saveDomains);
  }

  // Handle bridge token change
  if (bridgeTokenInput) {
    const saveToken = () => {
      const token = (bridgeTokenInput.value || '').trim();
      currentBridgeToken = token;
      chrome.storage.local.set({ bridgeToken: token }, () => {
        if (chrome.runtime.lastError) {
          if (footerStatusText) footerStatusText.textContent = 'Could not save the connection token.';
          return;
        }
        checkConnection();
      });
    };
    bridgeTokenInput.addEventListener('change', saveToken);
  }

  // Open App Button
  openAppBtn?.addEventListener('click', async () => {
    if (connectedPort) {
      try {
        const response = await fetch(`http://127.0.0.1:${connectedPort}/show`, {
          method: 'POST',
          headers: {
            'X-HyperFetch-Client': 'extension',
            'X-HyperFetch-Token': currentBridgeToken || ''
          },
          signal: AbortSignal.timeout(1200)
        });
        if (response.ok) return;
      } catch (e) {
        // An older desktop may not expose the show action.
      }
    }
    chrome.runtime.sendMessage({ action: 'launchApp' }, (launched) => {
      if (chrome.runtime.lastError || !launched) {
        window.location.href = 'hyperfetch://open';
      } else {
        setTimeout(checkConnection, 600);
      }
    });
  });

  // Retry Connection Button
  retryBtn?.addEventListener('click', () => {
    checkConnection();
  });

  function showHandoff(handoff) {
    if (!handoffStatus) return;
    if (!handoff || Date.now() - handoff.timestamp > 5 * 60 * 1000) {
      handoffStatus.textContent = '';
      return;
    }
    const messages = {
      accepted: 'Last download sent to HyperFetch.',
      waiting: 'Last download added to HyperFetch and waiting for a slot.',
      paused: 'Last download added to HyperFetch as paused.',
      browser: 'Last download continued in your browser.'
    };
    handoffStatus.textContent = messages[handoff.outcome] || '';
  }

  chrome.storage.session?.get('lastHandoff').then(({ lastHandoff }) => showHandoff(lastHandoff)).catch(() => {});
  function handleStorageChange(changes, area) {
    if (area === 'session' && changes.lastHandoff) showHandoff(changes.lastHandoff.newValue);
  }
  chrome.storage.onChanged.addListener(handleStorageChange);

  function checkConnection() {
    const check = ++connectionCheck;
    connectedPort = null;
    stopTransfersPolling();
    if (statusBadge) statusBadge.className = 'status-badge';
    if (statusText) statusText.textContent = 'Connecting...';
    renderTransfers([], 'Checking the desktop connection…');

    chrome.runtime.sendMessage({ action: 'checkStatus' }, (response) => {
      if (check !== connectionCheck) return;
      if (chrome.runtime.lastError || !response || !response.connected) {
        setOffline(response?.rejected === true);
      } else {
        setConnected(response.port);
      }
    });
  }

  function setConnected(port) {
    connectedPort = port;
    if (statusBadge) statusBadge.className = 'status-badge status-online';
    if (statusText) statusText.textContent = `Connected (${port})`;
    if (footerStatusText) {
      footerStatusText.textContent = `HyperFetch Local Bridge 127.0.0.1:${port}`;
    }

    startTransfersPolling();
  }

  function setOffline(rejected = false) {
    connectedPort = null;
    if (statusBadge) statusBadge.className = 'status-badge status-offline';
    if (statusText) statusText.textContent = rejected ? 'Connection rejected' : 'App unreachable';
    if (footerStatusText) footerStatusText.textContent = rejected
      ? 'Check the connection token in Advanced settings.'
      : 'Open HyperFetch, then recheck the connection.';
    stopTransfersPolling();
    renderTransfers([], 'Downloads unavailable');
  }

  function startTransfersPolling() {
    stopTransfersPolling();
    consecutiveErrors = 0;
    pollTransfers();
  }

  function stopTransfersPolling() {
    if (pollTimeoutId) {
      clearTimeout(pollTimeoutId);
      pollTimeoutId = null;
    }
  }

  function scheduleNextPoll(delayMs) {
    stopTransfersPolling();
    if (!connectedPort) return;
    pollTimeoutId = setTimeout(pollTransfers, delayMs);
  }

  async function pollTransfers() {
    if (!connectedPort) return;
    const check = connectionCheck;
    const port = connectedPort;
    try {
      const headers = {
        'X-HyperFetch-Client': 'extension',
        'X-HyperFetch-Token': currentBridgeToken || ''
      };
      let transfers = null;
      const resp = await fetch(`http://127.0.0.1:${port}/transfers`, {
        method: 'GET',
        cache: 'no-store',
        headers: headers,
        signal: AbortSignal.timeout(2500)
      });
      if (resp.ok) {
        const data = await resp.json();
        transfers = data.transfers || [];
      } else if (resp.status === 403 || resp.status === 404) {
        // Fallback to /queue if /transfers failed
        const qResp = await fetch(`http://127.0.0.1:${port}/queue`, {
          method: 'GET',
          cache: 'no-store',
          headers: headers,
          signal: AbortSignal.timeout(2500)
        });
        if (qResp.ok) {
          const qData = await qResp.json();
          transfers = qData.transfers || [];
        } else {
          throw new Error(`Queue fetch returned status ${qResp.status}`);
        }
      } else {
        throw new Error(`Transfers fetch returned status ${resp.status}`);
      }

      if (check !== connectionCheck) return;
      if (transfers !== null) {
        consecutiveErrors = 0;
        renderTransfers(transfers);

        // Adaptive polling schedule:
        // - Active downloads (downloading, connecting, probing): 1,500ms
        // - Completed/paused or idle items in queue: 3,500ms
        // - Empty queue: 5,000ms
        const hasActive = transfers.some(t => {
          const s = (t.status || '').toLowerCase();
          return s === 'downloading' || s === 'connecting' || s === 'probing';
        });

        let nextInterval = 5000;
        if (hasActive) {
          nextInterval = 1500;
        } else if (transfers.length > 0) {
          nextInterval = 3500;
        } else {
          nextInterval = 5000;
        }

        scheduleNextPoll(nextInterval);
      }
    } catch (e) {
      if (check !== connectionCheck) return;
      renderTransfers([], 'Could not refresh downloads. Retrying…');
      consecutiveErrors++;
      if (consecutiveErrors >= 3) {
        // Back off to 10,000ms after 3 consecutive failures
        scheduleNextPoll(10000);
      } else {
        scheduleNextPoll(5000);
      }
    }
  }

  function renderTransfers(transfers, emptyMessage = 'No active downloads') {
    if (transfersCountBadge) {
      transfersCountBadge.textContent = String(transfers.length);
    }
    if (!transfersList) return;

    if (!transfers || transfers.length === 0) {
      const message = document.createElement('div');
      message.className = 'transfers-empty';
      message.textContent = emptyMessage;
      transfersList.replaceChildren(message);
      return;
    }

    transfersList.innerHTML = transfers.map(t => {
      const reportedStatus = String(t.status || '').toLowerCase();
      const rawStatus = /^[a-z]+$/.test(reportedStatus) ? reportedStatus : 'queued';
      const statusLabel = rawStatus === 'queued' || rawStatus === 'pending'
        ? 'Waiting for a slot'
        : rawStatus.charAt(0).toUpperCase() + rawStatus.slice(1);
      const progressPercent = Math.min(100, Math.max(0, Math.round((t.progress || 0) * 100)));
      const speed = formatSpeed(t.speed);
      const eta = formatEta(t.eta);
      let metaText = statusLabel;
      if (rawStatus === 'downloading') {
        metaText = speed + (eta ? ` • ${eta}` : '');
      } else if (t.total_bytes && t.total_bytes > 0) {
        metaText = `${formatBytes(t.downloaded_bytes || 0)} of ${formatBytes(t.total_bytes)}`;
      }

      return `
        <div class="transfer-item">
          <div class="transfer-info">
            <span class="transfer-filename" title="${escapeHtml(t.filename || 'download')}">${escapeHtml(t.filename || 'download')}</span>
            <span class="status-pill status-${rawStatus}">${statusLabel}</span>
          </div>
          <div class="transfer-progress-track" role="progressbar" aria-label="Download progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${progressPercent}">
            <div class="transfer-progress-fill status-fill-${rawStatus}" style="width: ${progressPercent}%;"></div>
          </div>
          <div class="transfer-meta">
            <span class="transfer-speed">${metaText}</span>
            <span class="transfer-percent">${progressPercent}%</span>
          </div>
        </div>
      `;
    }).join('');
  }

  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
  }

  function formatSpeed(bytesPerSec) {
    if (!bytesPerSec || bytesPerSec <= 0) return '0 KB/s';
    if (bytesPerSec < 1024 * 1024) {
      return `${(bytesPerSec / 1024).toFixed(1)} KB/s`;
    }
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} MB/s`;
  }

  function formatEta(seconds) {
    if (!seconds || seconds <= 0 || !isFinite(seconds)) return '';
    if (seconds < 60) return `${Math.round(seconds)}s left`;
    if (seconds < 3600) {
      const mins = Math.floor(seconds / 60);
      const secs = Math.round(seconds % 60);
      return `${mins}m ${secs}s left`;
    }
    const hours = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${mins}m left`;
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  window.addEventListener('unload', () => {
    stopTransfersPolling();
  });
});
