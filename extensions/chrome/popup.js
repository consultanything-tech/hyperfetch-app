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

  let connectedPort = null;
  let pollIntervalId = null;
  let currentBridgeToken = '';

  // Load saved preferences
  chrome.storage.local.get([
    'enabled',
    'interceptAll',
    'minFileSize',
    'excludedDomains',
    'bridgeToken'
  ], (res) => {
    if (chrome.runtime.lastError) return;
    if (res) {
      if (res.enabled !== undefined) {
        interceptToggle.checked = res.enabled;
      }
      if (res.interceptAll) {
        scopeAll.checked = true;
      } else {
        scopeFiltered.checked = true;
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
  });

  // Handle toggle change
  interceptToggle.addEventListener('change', () => {
    const isEnabled = interceptToggle.checked;
    chrome.storage.local.set({ enabled: isEnabled });
  });

  // Handle scope change
  scopeFiltered.addEventListener('change', () => {
    if (scopeFiltered.checked) {
      chrome.storage.local.set({ interceptAll: false });
    }
  });

  scopeAll.addEventListener('change', () => {
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
      const domains = raw
        .split(/[\n,]+/)
        .map(d => d.trim().toLowerCase())
        .filter(Boolean);
      chrome.storage.local.set({ excludedDomains: domains });
    };
    excludedDomainsInput.addEventListener('input', saveDomains);
    excludedDomainsInput.addEventListener('change', saveDomains);
  }

  // Handle bridge token change
  if (bridgeTokenInput) {
    const saveToken = () => {
      const token = (bridgeTokenInput.value || '').trim();
      currentBridgeToken = token;
      chrome.storage.local.set({ bridgeToken: token });
    };
    bridgeTokenInput.addEventListener('input', saveToken);
    bridgeTokenInput.addEventListener('change', saveToken);
  }

  // Open App Button
  openAppBtn.addEventListener('click', () => {
    window.location.href = 'hyperfetch://open';
  });

  // Retry Connection Button
  retryBtn.addEventListener('click', () => {
    checkConnection();
  });

  // Initial connection check
  checkConnection();

  async function checkConnection() {
    statusBadge.className = 'status-badge';
    statusText.textContent = 'Connecting...';

    chrome.runtime.sendMessage({ action: 'checkStatus' }, (response) => {
      if (chrome.runtime.lastError || !response || !response.connected) {
        // Fallback direct probe from popup context
        probeDirectly();
      } else {
        setConnected(response.port);
      }
    });
  }

  async function probeDirectly() {
    const ports = [31415, 31416];
    for (const port of ports) {
      try {
        const headers = {
          'X-HyperFetch-Client': 'extension',
          'X-HyperFetch-Token': currentBridgeToken || ''
        };
        const resp = await fetch(`http://127.0.0.1:${port}/status`, {
          method: 'GET',
          cache: 'no-store',
          headers: headers
        });
        if (resp.ok) {
          setConnected(port);
          return;
        }
      } catch (e) {}
    }
    setOffline();
  }

  function setConnected(port) {
    connectedPort = port;
    statusBadge.className = 'status-badge status-online';
    statusText.textContent = `Connected (${port})`;
    if (footerStatusText) {
      footerStatusText.textContent = `HyperFetch Local Bridge 127.0.0.1:${port}`;
    }

    startTransfersPolling();
  }

  function setOffline() {
    connectedPort = null;
    statusBadge.className = 'status-badge status-offline';
    statusText.textContent = 'HyperFetch Offline';
    stopTransfersPolling();
    renderTransfers([]);
  }

  function startTransfersPolling() {
    stopTransfersPolling();
    pollTransfers();
    pollIntervalId = setInterval(pollTransfers, 2000);
  }

  function stopTransfersPolling() {
    if (pollIntervalId) {
      clearInterval(pollIntervalId);
      pollIntervalId = null;
    }
  }

  async function pollTransfers() {
    if (!connectedPort) return;
    try {
      const headers = {
        'X-HyperFetch-Client': 'extension',
        'X-HyperFetch-Token': currentBridgeToken || ''
      };
      const resp = await fetch(`http://127.0.0.1:${connectedPort}/transfers`, {
        method: 'GET',
        cache: 'no-store',
        headers: headers
      });
      if (resp.ok) {
        const data = await resp.json();
        renderTransfers(data.transfers || []);
      } else if (resp.status === 403 || resp.status === 404) {
        // Fallback to /queue if /transfers failed
        const qResp = await fetch(`http://127.0.0.1:${connectedPort}/queue`, {
          method: 'GET',
          cache: 'no-store',
          headers: headers
        });
        if (qResp.ok) {
          const qData = await qResp.json();
          renderTransfers(qData.transfers || []);
        }
      }
    } catch (e) {
      // Connection might have dropped
    }
  }

  function renderTransfers(transfers) {
    if (transfersCountBadge) {
      transfersCountBadge.textContent = String(transfers.length);
    }
    if (!transfersList) return;

    if (!transfers || transfers.length === 0) {
      transfersList.innerHTML = '<div class="transfers-empty">No active downloads</div>';
      return;
    }

    transfersList.innerHTML = transfers.map(t => {
      const rawStatus = (t.status || 'queued').toLowerCase();
      const statusLabel = rawStatus.charAt(0).toUpperCase() + rawStatus.slice(1);
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
          <div class="transfer-progress-track">
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
