/**
 * LinuxBox Manager - Frontend Application
 * 
 * Handles system info display and OTA update functionality
 * With i18n (internationalization) support
 */

// ============================================
// Configuration
// ============================================
const CONFIG = {
    API_BASE: '',  // Same origin
    // Version info URLs (try GitHub first, fallback to Gitee if unavailable)
    VERSION_URL: 'https://raw.githubusercontent.com/thirdreality/LinuxBox-Installer/refs/heads/main/version.json',
    VERSION_URL_GITEE: 'https://gitee.com/thirdreality/LinuxBox-Installer/raw/main/version.json',
    // Release base URL (for display only, actual download is handled by backend with dual-source support)
    RELEASE_BASE_URL: 'https://github.com/thirdreality/LinuxBox-Installer/releases/download',
    REFRESH_INTERVAL: 30000,  // 30 seconds
    TASK_POLL_INTERVAL: 2000,  // 2 seconds
};

// ============================================
// State Management
// ============================================
const state = {
    systemInfo: null,
    softwareInfo: null,
    versionInfo: null,
    connectionState: 'connecting',  // 'connecting' | 'connected' | 'failed'
    activeTab: 'system',
    upgradeInProgress: {},  // Track upgrades by software name
};

// ============================================
// DOM Elements
// ============================================
const elements = {
    connectionStatus: document.getElementById('connectionStatus'),
    connectionText: document.getElementById('connectionText'),
    systemInfoCard: document.getElementById('systemInfoCard'),
    otaContainer: document.getElementById('otaContainer'),
    toastContainer: document.getElementById('toastContainer'),
    refreshSystemBtn: document.getElementById('refreshSystemBtn'),
    refreshOtaBtn: document.getElementById('refreshOtaBtn'),
    langBtn: document.getElementById('langBtn'),
    langDropdown: document.getElementById('langDropdown'),
    currentLangText: document.getElementById('currentLangText'),
    restartBtn: document.getElementById('restartBtn'),
};

// ============================================
// i18n Helper
// ============================================
function t(key, params = {}) {
    return I18N.t(key, params);
}

// Language display mapping
const LANG_DISPLAY = {
    'en': 'EN',
    'zh-CN': '简',
    'zh-TW': '繁'
};

// ============================================
// Update all i18n elements in DOM
// ============================================
function updateI18nElements() {
    // Update elements with data-i18n attribute (skip dynamic status elements)
    document.querySelectorAll('[data-i18n]').forEach(el => {
        // Skip connection status text - it's updated dynamically
        if (el.id === 'connectionText') {
            return;
        }
        const key = el.getAttribute('data-i18n');
        el.textContent = t(key);
    });
    
    // Update elements with data-i18n-title attribute
    document.querySelectorAll('[data-i18n-title]').forEach(el => {
        const key = el.getAttribute('data-i18n-title');
        el.title = t(key);
    });
    
    // Update HTML lang attribute
    document.documentElement.lang = I18N.getLanguage();
    
    // Update current language display
    if (elements.currentLangText) {
        elements.currentLangText.textContent = LANG_DISPLAY[I18N.getLanguage()] || 'EN';
    }
    
    // Update active language option
    document.querySelectorAll('.lang-option').forEach(opt => {
        opt.classList.toggle('active', opt.dataset.lang === I18N.getLanguage());
    });
    
    // Update connection status text based on current state (pass undefined to keep state)
    updateConnectionStatus();
}

// ============================================
// Language Selector
// ============================================
function initLanguageSelector() {
    const selector = document.querySelector('.lang-selector');
    
    // Toggle dropdown
    elements.langBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        selector.classList.toggle('open');
    });
    
    // Close dropdown when clicking outside
    document.addEventListener('click', () => {
        selector.classList.remove('open');
    });
    
    // Language options
    document.querySelectorAll('.lang-option').forEach(opt => {
        opt.addEventListener('click', () => {
            const lang = opt.dataset.lang;
            if (I18N.setLanguage(lang)) {
                updateI18nElements();
                // Reload current view to update dynamic content
                if (state.activeTab === 'system' && state.systemInfo) {
                    renderSystemInfo(state.systemInfo);
                }
                if (state.activeTab === 'setting' && state.versionInfo) {
                    const installedSoftware = state.softwareInfo?.homeassistant_core?.software || [];
                    const upgrades = getUpgradeInfo(installedSoftware, state.versionInfo);
                    renderOtaTable(upgrades);
                }
            }
            selector.classList.remove('open');
        });
    });
}

// ============================================
// Utility Functions
// ============================================
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function compareVersions(v1, v2) {
    // Simple version comparison - returns true if v1 < v2
    if (!v1 || !v2) return false;
    
    const normalize = (v) => v.replace(/[^0-9.]/g, '').split('.').map(n => parseInt(n, 10) || 0);
    const parts1 = normalize(v1);
    const parts2 = normalize(v2);
    
    for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
        const p1 = parts1[i] || 0;
        const p2 = parts2[i] || 0;
        if (p1 < p2) return true;
        if (p1 > p2) return false;
    }
    return false;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ============================================
// Toast Notifications
// ============================================
function showToast(message, type = 'info', duration = 4000) {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    
    const iconPaths = {
        success: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline>',
        error: '<circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line>',
        warning: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line>',
        info: '<circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line>',
    };
    
    toast.innerHTML = `
        <svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            ${iconPaths[type] || iconPaths.info}
        </svg>
        <span class="toast-message">${escapeHtml(message)}</span>
        <button class="toast-close" onclick="this.parentElement.remove()">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
        </button>
    `;
    
    elements.toastContainer.appendChild(toast);
    
    if (duration > 0) {
        setTimeout(() => {
            toast.style.animation = 'slideIn 0.25s ease reverse';
            setTimeout(() => toast.remove(), 250);
        }, duration);
    }
    
    return toast;
}

// ============================================
// Connection Status
// ============================================
function updateConnectionStatus(connected, messageKey = '') {
    // Update connection state
    if (connected === true) {
        state.connectionState = 'connected';
    } else if (connected === false) {
        state.connectionState = 'failed';
    }
    // If connected is undefined/null, keep current state (for language switch)
    
    // Update indicator class
    const indicatorClass = state.connectionState === 'connected' ? 'online' : 
                          state.connectionState === 'failed' ? 'offline' : '';
    elements.connectionStatus.className = `status-indicator ${indicatorClass}`;
    
    // Update status text
    if (messageKey) {
        elements.connectionText.textContent = t(messageKey);
    } else {
        const statusKey = state.connectionState === 'connected' ? 'status.connected' :
                         state.connectionState === 'failed' ? 'status.failed' :
                         'status.connecting';
        elements.connectionText.textContent = t(statusKey);
    }
}

// ============================================
// Tab Navigation
// ============================================
function initTabs() {
    const tabButtons = document.querySelectorAll('.tab-btn');
    const tabPanels = document.querySelectorAll('.tab-panel');
    
    tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.dataset.tab;
            
            // Update active states
            tabButtons.forEach(b => b.classList.remove('active'));
            tabPanels.forEach(p => p.classList.remove('active'));
            
            btn.classList.add('active');
            document.getElementById(`${tab}-panel`).classList.add('active');
            
            state.activeTab = tab;
            
            // Load data if needed
            if (tab === 'setting' && !state.versionInfo) {
                loadOtaInfo();
            }
        });
    });
}

// ============================================
// System Info Display
// ============================================
function renderSystemInfo(data) {
    const infoItems = [
        { key: 'Device Model', i18nKey: 'info.deviceModel', value: data['Device Model'] },
        { key: 'Device Name', i18nKey: 'info.deviceName', value: data['Device Name'] },
        { key: 'Model ID', i18nKey: 'info.modelId', value: data['Model ID'] },
        { key: 'Version', i18nKey: 'info.version', value: data['Version'], highlight: true },
        { key: 'Build Number', i18nKey: 'info.buildNumber', value: data['Build Number'] },
        { key: 'Zigbee Support', i18nKey: 'info.zigbeeSupport', value: data['Zigbee Support'], badge: true },
        { key: 'Thread Support', i18nKey: 'info.threadSupport', value: data['Thread Support'], badge: true },
        { key: 'Memory', i18nKey: 'info.memory', value: data['Memory'] },
        { key: 'Storage', i18nKey: 'info.storage', value: data['Storage'] },
        { key: 'WiFi Connected', i18nKey: 'info.wifiConnected', value: data['WIFI Connected'], badge: true },
        { key: 'SSID', i18nKey: 'info.ssid', value: data['SSID'] },
        { key: 'IP Address', i18nKey: 'info.ipAddress', value: data['Ip Address'] },
        { key: 'MAC Address', i18nKey: 'info.macAddress', value: data['Mac Address'] },
        { key: 'Services', i18nKey: 'info.services', value: data['Services'] },
    ];
    
    const rows = infoItems.map(item => {
        if (item.value === undefined || item.value === null || item.value === '') {
            return '';  // Skip empty values
        }
        
        let valueHtml = '';
        if (item.badge) {
            const isPositive = item.value === true || item.value === 'true';
            const badgeText = t(isPositive ? 'badge.yes' : 'badge.no');
            valueHtml = `<span class="badge ${isPositive ? 'success' : 'warning'}">${badgeText}</span>`;
        } else {
            valueHtml = `<span class="${item.highlight ? 'highlight' : ''}">${escapeHtml(String(item.value))}</span>`;
        }
        
        return `
            <div class="info-row">
                <div class="info-label">${escapeHtml(t(item.i18nKey))}</div>
                <div class="info-value">${valueHtml}</div>
            </div>
        `;
    }).join('');
    
    elements.systemInfoCard.innerHTML = rows || `<div class="empty-state"><p>${t('empty.noSystemInfo')}</p></div>`;
}

async function loadSystemInfo() {
    elements.refreshSystemBtn.classList.add('loading');
    
    try {
        const response = await fetch(`${CONFIG.API_BASE}/api/system/info`);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        state.systemInfo = await response.json();
        renderSystemInfo(state.systemInfo);
        updateConnectionStatus(true);
        
    } catch (error) {
        console.error('Failed to load system info:', error);
        elements.systemInfoCard.innerHTML = `
            <div class="empty-state">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="12" cy="12" r="10"></circle>
                    <line x1="12" y1="8" x2="12" y2="12"></line>
                    <line x1="12" y1="16" x2="12.01" y2="16"></line>
                </svg>
                <p>${t('empty.loadFailed')}</p>
            </div>
        `;
        updateConnectionStatus(false, 'status.failed');
        showToast(t('toast.connectFailed'), 'error');
    } finally {
        elements.refreshSystemBtn.classList.remove('loading');
    }
}

// ============================================
// OTA Update Logic
// ============================================

// Package name to version.json key mapping
const PACKAGE_TO_VERSION_KEY = {
    'thirdreality-python3': 'python3',
    'thirdreality-hacore': 'hacore',
    'thirdreality-otbr-agent': 'otbr-agent',
    'thirdreality-zigbee-mqtt': 'zigbee-mqtt',
    'thirdreality-board-firmware': 'board-firmware',
    'thirdreality-music-assistant': 'music-assistant',
    'thirdreality-openhab': 'openhab',
    'thirdreality-zwave': 'zwave',
    'thirdreality-enocean': 'enocean',
    'thirdreality-bridge': 'thirdreality-bridge',
    'linuxbox-supervisor': 'linuxbox-supervisor',
    'linux-image-current-meson64': 'linux-image',
};

// Package display order (by importance)
const PACKAGE_ORDER = [
    'linux-image-current-meson64',
    'linuxbox-supervisor',
    'thirdreality-bridge',
    'thirdreality-board-firmware',
    'thirdreality-hacore',
    'thirdreality-zigbee-mqtt',
    'thirdreality-otbr-agent',
    'thirdreality-music-assistant',
    'thirdreality-openhab',
    'thirdreality-zwave',
    'thirdreality-enocean',
    'thirdreality-python3',
];

async function loadSoftwareInfo() {
    try {
        const response = await fetch(`${CONFIG.API_BASE}/api/v2/software/info`);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        state.softwareInfo = await response.json();
        return state.softwareInfo;
    } catch (error) {
        console.error('Failed to load software info:', error);
        throw error;
    }
}

async function loadVersionInfo() {
    // Try GitHub first, fallback to Gitee if unavailable
    const urls = [CONFIG.VERSION_URL, CONFIG.VERSION_URL_GITEE];
    
    for (let i = 0; i < urls.length; i++) {
        try {
            const url = urls[i];
            const isGitee = url === CONFIG.VERSION_URL_GITEE;
            const sourceName = isGitee ? 'Gitee' : 'GitHub';
            
            if (isGitee) {
                console.log('GitHub version URL failed, trying Gitee...');
            }
            
            // Create timeout controller for better browser compatibility
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 seconds timeout
            
            try {
                const response = await fetch(url, {
                    method: 'GET',
                    headers: {
                        'Accept': 'application/json',
                    },
                    signal: controller.signal,
                });
                
                clearTimeout(timeoutId);
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                
                state.versionInfo = await response.json();
                
                if (isGitee) {
                    console.log('Successfully loaded version info from Gitee');
                }
                
                return state.versionInfo;
            } catch (fetchError) {
                clearTimeout(timeoutId);
                throw fetchError;
            }
        } catch (error) {
            const sourceName = urls[i] === CONFIG.VERSION_URL ? 'GitHub' : 'Gitee';
            console.error(`Failed to load version info from ${sourceName}:`, error);
            
            // If this is the last URL, throw the error
            if (i === urls.length - 1) {
                throw new Error(`Failed to load version info from all sources: ${error.message}`);
            }
            // Otherwise, continue to next URL
        }
    }
}

function getUpgradeInfo(installedSoftware, versionInfo) {
    const upgrades = [];
    const haVersions = versionInfo.homeassistant || {};
    
    // installedSoftware is now an object: { "package-name": "version", ... }
    Object.entries(installedSoftware).forEach(([packageName, currentVersion]) => {
        // Skip if no version
        if (!currentVersion) {
            return;
        }
        
        // Map package name to version.json key
        const versionKey = PACKAGE_TO_VERSION_KEY[packageName];
        
        if (!versionKey) {
            // Unknown package, still show it but no update available
            upgrades.push({
                index: upgrades.length + 1,
                packageName: packageName,
                versionKey: null,
                displayName: formatSoftwareName(packageName),
                currentVersion: currentVersion,
                newVersion: null,
                release: null,
            });
            return;
        }
        
        // Check if there's a newer version available in version.json
        const versionData = haVersions[versionKey];
        
        if (versionData && versionData.version && versionData.release) {
            const newVersion = versionData.version;
            const release = versionData.release;
            const hasUpdate = compareVersions(currentVersion, newVersion);
            
            upgrades.push({
                index: upgrades.length + 1,
                packageName: packageName,
                versionKey: versionKey,
                displayName: formatSoftwareName(packageName),
                currentVersion: currentVersion,
                newVersion: hasUpdate ? newVersion : null,
                release: hasUpdate ? release : null,
            });
        } else {
            // Software installed but no version info available online
            upgrades.push({
                index: upgrades.length + 1,
                packageName: packageName,
                versionKey: versionKey,
                displayName: formatSoftwareName(packageName),
                currentVersion: currentVersion,
                newVersion: null,
                release: null,
            });
        }
    });
    
    // Sort by predefined order (importance)
    upgrades.sort((a, b) => {
        const orderA = PACKAGE_ORDER.indexOf(a.packageName);
        const orderB = PACKAGE_ORDER.indexOf(b.packageName);
        // If not in the list, put at the end
        const indexA = orderA === -1 ? 999 : orderA;
        const indexB = orderB === -1 ? 999 : orderB;
        return indexA - indexB;
    });
    
    // Re-index after sorting
    upgrades.forEach((item, index) => {
        item.index = index + 1;
    });
    
    return upgrades;
}

function formatSoftwareName(packageName) {
    // Use i18n for software names
    const i18nKey = `software.${packageName}`;
    const translated = t(i18nKey);
    // If translation exists (not returning the key itself), use it
    if (translated !== i18nKey) {
        return translated;
    }
    // Fallback to original package name
    return packageName;
}

function renderOtaTable(upgrades) {
    if (upgrades.length === 0) {
        elements.otaContainer.innerHTML = `
            <div class="empty-state">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
                    <polyline points="22 4 12 14.01 9 11.01"></polyline>
                </svg>
                <p>${t('empty.noSoftware')}</p>
            </div>
        `;
        return;
    }
    
    const rows = upgrades.map(sw => {
        const upgradeCell = sw.newVersion 
            ? `<button class="upgrade-btn" data-package="${escapeHtml(sw.packageName)}" data-version-key="${escapeHtml(sw.versionKey || '')}" data-version="${escapeHtml(sw.newVersion)}" data-release="${escapeHtml(sw.release)}">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                        <polyline points="7 10 12 15 17 10"/>
                        <line x1="12" y1="15" x2="12" y2="3"/>
                    </svg>
                    ${t('ota.upgradeTo')} ${escapeHtml(sw.newVersion)}
               </button>`
            : `<span class="no-update">${t('ota.noUpdate')}</span>`;
        
        return `
            <tr data-package="${escapeHtml(sw.packageName)}">
                <td data-label="${t('ota.table.no')}">${sw.index}</td>
                <td data-label="${t('ota.table.software')}" class="software-name">${escapeHtml(sw.displayName)}</td>
                <td data-label="${t('ota.table.version')}" class="version-current">${escapeHtml(sw.currentVersion)}</td>
                <td data-label="${t('ota.table.upgrade')}">${upgradeCell}</td>
            </tr>
        `;
    }).join('');
    
    elements.otaContainer.innerHTML = `
        <table class="ota-table">
            <thead>
                <tr>
                    <th style="width: 10%;">${t('ota.table.no')}</th>
                    <th style="width: 30%;">${t('ota.table.software')}</th>
                    <th style="width: 30%; white-space: nowrap;">${t('ota.table.version')}</th>
                    <th style="width: 30%;">${t('ota.table.upgrade')}</th>
                </tr>
            </thead>
            <tbody>
                ${rows}
            </tbody>
        </table>
    `;
    
    // Add click handlers for upgrade buttons
    elements.otaContainer.querySelectorAll('.upgrade-btn').forEach(btn => {
        btn.addEventListener('click', () => handleUpgrade(btn));
    });
}

async function loadOtaInfo() {
    elements.refreshOtaBtn.classList.add('loading');
    
    try {
        // Load both software info and version info in parallel
        const [softwareInfo, versionInfo] = await Promise.all([
            loadSoftwareInfo(),
            loadVersionInfo()
        ]);
        
        // softwareInfo is now a direct object: { "package-name": "version", ... }
        const installedSoftware = softwareInfo || {};
        
        // Calculate upgrades
        const upgrades = getUpgradeInfo(installedSoftware, versionInfo);
        
        // Render the table
        renderOtaTable(upgrades);
        
        updateConnectionStatus(true);
        
    } catch (error) {
        console.error('Failed to load OTA info:', error);
        elements.otaContainer.innerHTML = `
            <div class="empty-state">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="12" cy="12" r="10"></circle>
                    <line x1="12" y1="8" x2="12" y2="12"></line>
                    <line x1="12" y1="16" x2="12.01" y2="16"></line>
                </svg>
                <p>${t('empty.updateFailed')}</p>
            </div>
        `;
        showToast(t('toast.updateFailed'), 'error');
    } finally {
        elements.refreshOtaBtn.classList.remove('loading');
    }
}

// ============================================
// Upgrade Handler
// ============================================
async function handleUpgrade(btn) {
    const packageName = btn.dataset.package;
    const versionKey = btn.dataset.versionKey;
    const version = btn.dataset.version;
    const release = btn.dataset.release;
    
    if (state.upgradeInProgress[packageName]) {
        showToast(t('toast.upgradeInProgress'), 'warning');
        return;
    }
    
    // Confirm upgrade
    const displayName = formatSoftwareName(packageName);
    const confirmMsg = t('confirm.upgrade', { software: displayName, version: version });
    if (!confirm(confirmMsg)) {
        return;
    }
    
    state.upgradeInProgress[packageName] = true;
    
    // Update button state
    btn.disabled = true;
    btn.classList.add('loading');
    btn.innerHTML = `
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M23 4v6h-6"/>
            <path d="M1 20v-6h6"/>
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
        </svg>
        ${t('ota.upgrading')}
    `;
    
    // Add progress bar below the button's row
    const row = btn.closest('tr');
    const progressRow = document.createElement('tr');
    progressRow.className = 'progress-row';
    progressRow.innerHTML = `
        <td colspan="4">
            <div class="progress-container">
                <div class="progress-bar">
                    <div class="progress-fill" style="width: 0%"></div>
                </div>
                <div class="progress-text">${t('progress.preparing')}</div>
            </div>
        </td>
    `;
    row.insertAdjacentElement('afterend', progressRow);
    
    const progressFill = progressRow.querySelector('.progress-fill');
    const progressText = progressRow.querySelector('.progress-text');
    
    try {
        // Call OTA upgrade API
        const response = await fetch(`${CONFIG.API_BASE}/api/ota/upgrade`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                package: packageName,
                versionKey: versionKey,
                version: version,
                release: release,
            }),
        });
        
        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error || `HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        
        if (!result.success) {
            throw new Error(result.error || 'Upgrade request failed');
        }
        
        showToast(t('toast.upgradeStarted', { software: displayName }), 'success');
        
        // Start polling for progress
        pollUpgradeProgress(packageName, progressFill, progressText, btn, progressRow);
        
    } catch (error) {
        console.error('Upgrade failed:', error);
        showToast(t('toast.upgradeFailed', { error: error.message }), 'error');
        
        // Reset button state
        btn.disabled = false;
        btn.classList.remove('loading');
        btn.innerHTML = `
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7 10 12 15 17 10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
            </svg>
            ${t('ota.upgradeTo')} ${version}
        `;
        
        // Remove progress row
        progressRow.remove();
        
        state.upgradeInProgress[packageName] = false;
    }
}

async function pollUpgradeProgress(packageName, progressFill, progressText, btn, progressRow) {
    const displayName = formatSoftwareName(packageName);
    let lastProgress = 0;
    
    const poll = async () => {
        try {
            const response = await fetch(`${CONFIG.API_BASE}/api/task/info?task=ota`);
            if (!response.ok) throw new Error('Failed to get task info');
            
            const data = await response.json();
            const taskInfo = data.data || {};
            
            const progress = taskInfo.progress || 0;
            const status = taskInfo.status || 'idle';
            const message = taskInfo.message || '';
            
            // Update progress bar
            progressFill.style.width = `${progress}%`;
            // Translate OTA message from backend to current language
            const translatedMessage = message ? I18N.translateOtaMessage(message) : `${t('progress.downloading')} ${progress}%`;
            progressText.textContent = translatedMessage;
            
            lastProgress = progress;
            
            if (status === 'success' || status === 'completed') {
                // Upgrade completed
                showToast(t('toast.upgradeSuccess', { software: displayName }), 'success');
                
                // Update button to show "已是最新"
                btn.outerHTML = `<span class="no-update">${t('ota.noUpdate')}</span>`;
                
                // Remove progress row after animation
                setTimeout(() => {
                    progressRow.remove();
                }, 1000);
                
                state.upgradeInProgress[packageName] = false;
                
                // Reload OTA info to reflect new version
                setTimeout(() => loadOtaInfo(), 2000);
                
            } else if (status === 'failed' || status === 'error') {
                // Upgrade failed - translate error message
                const translatedError = message ? I18N.translateOtaMessage(message) : t('progress.upgradeFailed', { error: 'Unknown error' });
                throw new Error(translatedError);
                
            } else {
                // Continue polling
                setTimeout(poll, CONFIG.TASK_POLL_INTERVAL);
            }
            
        } catch (error) {
            console.error('Progress poll error:', error);
            showToast(t('toast.upgradeFailed', { error: error.message }), 'error');
            
            // Reset state
            btn.disabled = false;
            btn.classList.remove('loading');
            progressRow.remove();
            state.upgradeInProgress[packageName] = false;
        }
    };
    
    // Start polling
    setTimeout(poll, CONFIG.TASK_POLL_INTERVAL);
}

// ============================================
// System Control Functions
// ============================================

// MD5 hash function for signature
function md5(string) {
    // Simple MD5 implementation for signature
    function md5cycle(x, k) {
        var a = x[0], b = x[1], c = x[2], d = x[3];
        a = ff(a, b, c, d, k[0], 7, -680876936);
        d = ff(d, a, b, c, k[1], 12, -389564586);
        c = ff(c, d, a, b, k[2], 17, 606105819);
        b = ff(b, c, d, a, k[3], 22, -1044525330);
        a = ff(a, b, c, d, k[4], 7, -176418897);
        d = ff(d, a, b, c, k[5], 12, 1200080426);
        c = ff(c, d, a, b, k[6], 17, -1473231341);
        b = ff(b, c, d, a, k[7], 22, -45705983);
        a = ff(a, b, c, d, k[8], 7, 1770035416);
        d = ff(d, a, b, c, k[9], 12, -1958414417);
        c = ff(c, d, a, b, k[10], 17, -42063);
        b = ff(b, c, d, a, k[11], 22, -1990404162);
        a = ff(a, b, c, d, k[12], 7, 1804603682);
        d = ff(d, a, b, c, k[13], 12, -40341101);
        c = ff(c, d, a, b, k[14], 17, -1502002290);
        b = ff(b, c, d, a, k[15], 22, 1236535329);
        a = gg(a, b, c, d, k[1], 5, -165796510);
        d = gg(d, a, b, c, k[6], 9, -1069501632);
        c = gg(c, d, a, b, k[11], 14, 643717713);
        b = gg(b, c, d, a, k[0], 20, -373897302);
        a = gg(a, b, c, d, k[5], 5, -701558691);
        d = gg(d, a, b, c, k[10], 9, 38016083);
        c = gg(c, d, a, b, k[15], 14, -660478335);
        b = gg(b, c, d, a, k[4], 20, -405537848);
        a = gg(a, b, c, d, k[9], 5, 568446438);
        d = gg(d, a, b, c, k[14], 9, -1019803690);
        c = gg(c, d, a, b, k[3], 14, -187363961);
        b = gg(b, c, d, a, k[8], 20, 1163531501);
        a = gg(a, b, c, d, k[13], 5, -1444681467);
        d = gg(d, a, b, c, k[2], 9, -51403784);
        c = gg(c, d, a, b, k[7], 14, 1735328473);
        b = gg(b, c, d, a, k[12], 20, -1926607734);
        a = hh(a, b, c, d, k[5], 4, -378558);
        d = hh(d, a, b, c, k[8], 11, -2022574463);
        c = hh(c, d, a, b, k[11], 16, 1839030562);
        b = hh(b, c, d, a, k[14], 23, -35309556);
        a = hh(a, b, c, d, k[1], 4, -1530992060);
        d = hh(d, a, b, c, k[4], 11, 1272893353);
        c = hh(c, d, a, b, k[7], 16, -155497632);
        b = hh(b, c, d, a, k[10], 23, -1094730640);
        a = hh(a, b, c, d, k[13], 4, 681279174);
        d = hh(d, a, b, c, k[0], 11, -358537222);
        c = hh(c, d, a, b, k[3], 16, -722521979);
        b = hh(b, c, d, a, k[6], 23, 76029189);
        a = hh(a, b, c, d, k[9], 4, -640364487);
        d = hh(d, a, b, c, k[12], 11, -421815835);
        c = hh(c, d, a, b, k[15], 16, 530742520);
        b = hh(b, c, d, a, k[2], 23, -995338651);
        a = ii(a, b, c, d, k[0], 6, -198630844);
        d = ii(d, a, b, c, k[7], 10, 1126891415);
        c = ii(c, d, a, b, k[14], 15, -1416354905);
        b = ii(b, c, d, a, k[5], 21, -57434055);
        a = ii(a, b, c, d, k[12], 6, 1700485571);
        d = ii(d, a, b, c, k[3], 10, -1894986606);
        c = ii(c, d, a, b, k[10], 15, -1051523);
        b = ii(b, c, d, a, k[1], 21, -2054922799);
        a = ii(a, b, c, d, k[8], 6, 1873313359);
        d = ii(d, a, b, c, k[15], 10, -30611744);
        c = ii(c, d, a, b, k[6], 15, -1560198380);
        b = ii(b, c, d, a, k[13], 21, 1309151649);
        a = ii(a, b, c, d, k[4], 6, -145523070);
        d = ii(d, a, b, c, k[11], 10, -1120210379);
        c = ii(c, d, a, b, k[2], 15, 718787259);
        b = ii(b, c, d, a, k[9], 21, -343485551);
        x[0] = add32(a, x[0]);
        x[1] = add32(b, x[1]);
        x[2] = add32(c, x[2]);
        x[3] = add32(d, x[3]);
    }
    function cmn(q, a, b, x, s, t) {
        a = add32(add32(a, q), add32(x, t));
        return add32((a << s) | (a >>> (32 - s)), b);
    }
    function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
    function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
    function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
    function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
    function md5blk(s) {
        var md5blks = [], i;
        for (i = 0; i < 64; i += 4) {
            md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
        }
        return md5blks;
    }
    function md5blk_array(a) {
        var md5blks = [], i;
        for (i = 0; i < 64; i += 4) {
            md5blks[i >> 2] = a[i] + (a[i + 1] << 8) + (a[i + 2] << 16) + (a[i + 3] << 24);
        }
        return md5blks;
    }
    function md51(s) {
        var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i, length, tail, tmp, lo, hi;
        for (i = 64; i <= n; i += 64) {
            md5cycle(state, md5blk(s.substring(i - 64, i)));
        }
        s = s.substring(i - 64);
        length = s.length;
        tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        for (i = 0; i < length; i++) {
            tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
        }
        tail[i >> 2] |= 0x80 << ((i % 4) << 3);
        if (i > 55) {
            md5cycle(state, tail);
            for (i = 0; i < 16; i++) tail[i] = 0;
        }
        tmp = n * 8;
        tmp = tmp.toString(16).match(/(.*?)(.{0,8})$/);
        lo = parseInt(tmp[2], 16);
        hi = parseInt(tmp[1], 16) || 0;
        tail[14] = lo;
        tail[15] = hi;
        md5cycle(state, tail);
        return state;
    }
    function rhex(n) {
        var s = '', j;
        for (j = 0; j < 4; j++) {
            s += ((n >> (j * 8 + 4)) & 0x0F).toString(16) + ((n >> (j * 8)) & 0x0F).toString(16);
        }
        return s;
    }
    function hex(x) {
        for (var i = 0; i < x.length; i++) {
            x[i] = rhex(x[i]);
        }
        return x.join('');
    }
    function add32(a, b) {
        return (a + b) & 0xFFFFFFFF;
    }
    return hex(md51(string));
}

// Generate signature for API request
function generateSignature(params) {
    const secretKey = 'ThirdReality';
    const sortedKeys = Object.keys(params).sort();
    const paramString = sortedKeys.map(k => `${k}=${params[k]}`).join('&');
    const securityString = `${paramString}&${secretKey}`;
    return md5(securityString);
}

// Handle restart button click
async function handleRestart() {
    // Confirm restart
    const confirmMsg = t('system.restart.confirm');
    if (!confirm(confirmMsg)) {
        return;
    }
    
    const btn = elements.restartBtn;
    btn.disabled = true;
    btn.classList.add('loading');
    
    try {
        // Build request with signature
        const params = { command: 'reboot' };
        const signature = generateSignature(params);
        const body = `command=reboot&_sig=${signature}`;
        
        const response = await fetch(`${CONFIG.API_BASE}/api/system/command`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
        });
        
        const result = await response.json();
        
        if (result.success) {
            showToast(t('toast.restartSuccess'), 'success', 10000);
            // Disable all interactive elements
            document.querySelectorAll('button').forEach(b => b.disabled = true);
        } else {
            throw new Error(result.error || 'Restart failed');
        }
        
    } catch (error) {
        console.error('Restart failed:', error);
        showToast(t('toast.restartFailed', { error: error.message }), 'error');
        btn.disabled = false;
        btn.classList.remove('loading');
    }
}

// ============================================
// Event Listeners
// ============================================
function initEventListeners() {
    // Refresh buttons
    elements.refreshSystemBtn.addEventListener('click', loadSystemInfo);
    elements.refreshOtaBtn.addEventListener('click', loadOtaInfo);
    
    // Restart button
    if (elements.restartBtn) {
        elements.restartBtn.addEventListener('click', handleRestart);
    }
    
    // Auto refresh system info periodically
    setInterval(() => {
        if (state.activeTab === 'system') {
            loadSystemInfo();
        }
    }, CONFIG.REFRESH_INTERVAL);
}

// ============================================
// Initialize Application
// ============================================
async function init() {
    console.log('LinuxBox Manager initialized');
    
    // Initialize i18n
    I18N.init();
    
    // Update all i18n elements
    updateI18nElements();
    
    // Initialize language selector
    initLanguageSelector();
    
    // Initialize tabs
    initTabs();
    
    // Initialize event listeners
    initEventListeners();
    
    // Load initial data
    await loadSystemInfo();
}

// Start the application when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
