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

  // Load saved preferences
  chrome.storage.local.get(['enabled', 'interceptAll'], (res) => {
    if (chrome.runtime.lastError) return;
    if (res && res.enabled !== undefined) {
      interceptToggle.checked = res.enabled;
    }
    if (res && res.interceptAll) {
      scopeAll.checked = true;
    } else {
      scopeFiltered.checked = true;
    }
  });

  // Handle toggle change
  interceptToggle.addEventListener('change', () => {
    const isEnabled = interceptToggle.checked;
    chrome.storage.local.set({ enabled: isEnabled }, () => {
      const _ = chrome.runtime.lastError;
    });
  });

  // Handle scope change
  scopeFiltered.addEventListener('change', () => {
    if (scopeFiltered.checked) {
      chrome.storage.local.set({ interceptAll: false }, () => {
        const _ = chrome.runtime.lastError;
      });
    }
  });

  scopeAll.addEventListener('change', () => {
    if (scopeAll.checked) {
      chrome.storage.local.set({ interceptAll: true }, () => {
        const _ = chrome.runtime.lastError;
      });
    }
  });

  // Open App Button
  openAppBtn.addEventListener('click', () => {
    // Attempt opening custom scheme
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
        const resp = await fetch(`http://127.0.0.1:${port}/status`, {
          method: 'GET',
          cache: 'no-store',
          headers: {
            'X-HyperFetch-Client': 'extension'
          }
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
    statusBadge.className = 'status-badge status-online';
    statusText.textContent = `Connected (${port})`;
  }

  function setOffline() {
    statusBadge.className = 'status-badge status-offline';
    statusText.textContent = 'HyperFetch Offline';
  }
});
