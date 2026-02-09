/**
 * LinuxBox Manager - Internationalization (i18n)
 * 
 * Supports: English (en), Simplified Chinese (zh-CN), Traditional Chinese (zh-TW)
 */

const I18N = {
    // Current language
    currentLang: 'en',
    
    // Supported languages
    languages: {
        'en': 'English',
        'zh-CN': '简体中文',
        'zh-TW': '繁體中文'
    },
    
    // Translations
    translations: {
        'en': {
            // Header
            'app.title': 'LinuxBox',
            'status.connecting': 'Connecting...',
            'status.connected': 'Connected',
            'status.disconnected': 'Disconnected',
            'status.failed': 'Connection Failed',
            
            // Tabs
            'tab.system': 'System',
            'tab.setting': 'Setting',
            
            // System Panel
            'panel.system.title': 'System Information',
            'btn.refresh': 'Refresh',
            
            // System Info Labels
            'info.deviceModel': 'Device Model',
            'info.deviceName': 'Device Name',
            'info.modelId': 'Model ID',
            'info.version': 'Version',
            'info.buildNumber': 'Build Number',
            'info.zigbeeSupport': 'Zigbee Support',
            'info.threadSupport': 'Thread Support',
            'info.memory': 'Memory',
            'info.storage': 'Storage',
            'info.wifiConnected': 'WiFi Connected',
            'info.ssid': 'SSID',
            'info.ipAddress': 'IP Address',
            'info.macAddress': 'MAC Address',
            'info.services': 'Services',
            
            // Badge
            'badge.yes': 'YES',
            'badge.no': 'NO',
            
            // Setting Panel
            'panel.setting.title': 'Software Update',
            'btn.checkUpdate': 'Check Update',
            
            // OTA Section
            'ota.title': 'OTA Update',
            'ota.table.no': 'No.',
            'ota.table.software': 'Software',
            'ota.table.version': 'Version',
            'ota.table.upgrade': 'Upgrade',
            'ota.noUpdate': 'Up to date',
            'ota.upgradeTo': 'Upgrade to',
            'ota.upgrading': 'Upgrading...',
            
            // Software Names (package names)
            'software.thirdreality-python3': 'Python 3',
            'software.thirdreality-hacore': 'Home Assistant Core',
            'software.thirdreality-otbr-agent': 'Thread Border Router',
            'software.thirdreality-zigbee-mqtt': 'Zigbee2MQTT',
            'software.thirdreality-board-firmware': 'Board Firmware',
            'software.thirdreality-music-assistant': 'Music Assistant',
            'software.thirdreality-openhab': 'OpenHAB',
            'software.thirdreality-zwave': 'Z-Wave',
            'software.thirdreality-enocean': 'EnOcean',
            'software.thirdreality-bridge': 'LinuxBox Bridge',
            'software.linuxbox-supervisor': 'LinuxBox Supervisor',
            'software.linux-image-current-meson64': 'LinuxBox Kernel',
            
            // Loading & Empty States
            'loading': 'Loading...',
            'loading.checkingUpdate': 'Checking for updates...',
            'empty.noSystemInfo': 'No system information available',
            'empty.loadFailed': 'Failed to load system information',
            'empty.noSoftware': 'No software available for update',
            'empty.updateFailed': 'Failed to get update information',
            
            // Progress (OTA messages from backend)
            'progress.preparing': 'Preparing upgrade for {software}...',
            'progress.downloading': 'Downloading {software} v{version}...',
            'progress.downloadingSize': 'Downloading... {downloaded}MB / {total}MB',
            'progress.installing': 'Download complete, installing {software}...',
            'progress.fixingDeps': 'Fixing dependencies...',
            'progress.cleaning': 'Cleaning up...',
            'progress.complete': '{software} upgrade successful!',
            'progress.upgraded': '{software} has been upgraded to v{version}',
            'progress.downloadFailed': 'Download failed: {reason}',
            'progress.installTimeout': 'Installation timed out',
            'progress.upgradeFailed': 'Upgrade failed: {error}',
            'progress.installFailed': 'Installation failed: {error}',
            
            // Confirm Dialog
            'confirm.upgrade': 'Are you sure you want to upgrade {software} to {version}?\n\nPlease do not close the page or disconnect during the upgrade.',
            
            // Toast Messages
            'toast.connectFailed': 'Failed to connect to device',
            'toast.updateFailed': 'Failed to get update information',
            'toast.upgradeStarted': '{software} upgrade started',
            'toast.upgradeSuccess': '{software} upgrade successful!',
            'toast.upgradeFailed': 'Upgrade failed: {error}',
            'toast.upgradeInProgress': 'Upgrade is already in progress',
            
            // System Control
            'system.control.title': 'System Control',
            'system.restart.label': 'Restart Device',
            'system.restart.desc': 'Restart the LinuxBox device',
            'system.restart.btn': 'Restart',
            'system.restart.confirm': 'Are you sure you want to restart the device?\n\nThe device will be unavailable for a few minutes.',
            'toast.restartSuccess': 'Device is restarting...',
            'toast.restartFailed': 'Failed to restart: {error}',
            
            // Language
            'language': 'Language',
        },
        
        'zh-CN': {
            // Header
            'app.title': 'LinuxBox',
            'status.connecting': '连接中...',
            'status.connected': '已连接',
            'status.disconnected': '连接断开',
            'status.failed': '连接失败',
            
            // Tabs
            'tab.system': '系统',
            'tab.setting': '设置',
            
            // System Panel
            'panel.system.title': '系统信息',
            'btn.refresh': '刷新',
            
            // System Info Labels
            'info.deviceModel': '设备型号',
            'info.deviceName': '设备名称',
            'info.modelId': '型号 ID',
            'info.version': '版本',
            'info.buildNumber': '构建号',
            'info.zigbeeSupport': 'Zigbee 支持',
            'info.threadSupport': 'Thread 支持',
            'info.memory': '内存',
            'info.storage': '存储',
            'info.wifiConnected': 'WiFi 已连接',
            'info.ssid': 'SSID',
            'info.ipAddress': 'IP 地址',
            'info.macAddress': 'MAC 地址',
            'info.services': '服务',
            
            // Badge
            'badge.yes': '是',
            'badge.no': '否',
            
            // Setting Panel
            'panel.setting.title': '软件更新',
            'btn.checkUpdate': '检查更新',
            
            // OTA Section
            'ota.title': 'OTA 更新',
            'ota.table.no': '序号',
            'ota.table.software': '软件',
            'ota.table.version': '版本',
            'ota.table.upgrade': '升级',
            'ota.noUpdate': '已是最新',
            'ota.upgradeTo': '升级到',
            'ota.upgrading': '升级中...',
            
            // Software Names (package names)
            'software.thirdreality-python3': 'Python 3',
            'software.thirdreality-hacore': 'Home Assistant Core',
            'software.thirdreality-otbr-agent': 'Thread 边界路由器',
            'software.thirdreality-zigbee-mqtt': 'Zigbee2MQTT',
            'software.thirdreality-board-firmware': '子板固件',
            'software.thirdreality-music-assistant': '音乐助手',
            'software.thirdreality-openhab': 'OpenHAB',
            'software.thirdreality-zwave': 'Z-Wave',
            'software.thirdreality-enocean': 'EnOcean',
            'software.thirdreality-bridge': 'LinuxBox 数据路由',
            'software.linuxbox-supervisor': 'LinuxBox 管理器',
            'software.linux-image-current-meson64': 'LinuxBox 内核',
            
            // Loading & Empty States
            'loading': '加载中...',
            'loading.checkingUpdate': '检查更新中...',
            'empty.noSystemInfo': '暂无系统信息',
            'empty.loadFailed': '无法加载系统信息',
            'empty.noSoftware': '没有可更新的软件',
            'empty.updateFailed': '无法获取更新信息',
            
            // Progress (OTA messages from backend)
            'progress.preparing': '准备升级 {software}...',
            'progress.downloading': '正在下载 {software} v{version}...',
            'progress.downloadingSize': '下载中... {downloaded}MB / {total}MB',
            'progress.installing': '下载完成，正在安装 {software}...',
            'progress.fixingDeps': '正在修复依赖...',
            'progress.cleaning': '正在清理...',
            'progress.complete': '{software} 升级成功！',
            'progress.upgraded': '{software} 已成功升级到 v{version}',
            'progress.downloadFailed': '下载失败: {reason}',
            'progress.installTimeout': '安装超时',
            'progress.upgradeFailed': '升级失败: {error}',
            'progress.installFailed': '安装失败: {error}',
            
            // Confirm Dialog
            'confirm.upgrade': '确定要将 {software} 升级到 {version} 吗？\n\n升级过程中请勿关闭页面或断开设备连接。',
            
            // Toast Messages
            'toast.connectFailed': '无法连接到设备',
            'toast.updateFailed': '无法获取更新信息',
            'toast.upgradeStarted': '{software} 升级已开始',
            'toast.upgradeSuccess': '{software} 升级成功！',
            'toast.upgradeFailed': '升级失败: {error}',
            'toast.upgradeInProgress': '升级正在进行中',
            
            // System Control
            'system.control.title': '系统控制',
            'system.restart.label': '重启设备',
            'system.restart.desc': '重启 LinuxBox 设备',
            'system.restart.btn': '重启',
            'system.restart.confirm': '确定要重启设备吗？\n\n设备将在几分钟内不可用。',
            'toast.restartSuccess': '设备正在重启...',
            'toast.restartFailed': '重启失败: {error}',
            
            // Language
            'language': '语言',
        },
        
        'zh-TW': {
            // Header
            'app.title': 'LinuxBox',
            'status.connecting': '連接中...',
            'status.connected': '已連接',
            'status.disconnected': '連接中斷',
            'status.failed': '連接失敗',
            
            // Tabs
            'tab.system': '系統',
            'tab.setting': '設定',
            
            // System Panel
            'panel.system.title': '系統資訊',
            'btn.refresh': '重新整理',
            
            // System Info Labels
            'info.deviceModel': '裝置型號',
            'info.deviceName': '裝置名稱',
            'info.modelId': '型號 ID',
            'info.version': '版本',
            'info.buildNumber': '構建號',
            'info.zigbeeSupport': 'Zigbee 支援',
            'info.threadSupport': 'Thread 支援',
            'info.memory': '記憶體',
            'info.storage': '儲存空間',
            'info.wifiConnected': 'WiFi 已連接',
            'info.ssid': 'SSID',
            'info.ipAddress': 'IP 位址',
            'info.macAddress': 'MAC 位址',
            'info.services': '服務',
            
            // Badge
            'badge.yes': '是',
            'badge.no': '否',
            
            // Setting Panel
            'panel.setting.title': '軟體更新',
            'btn.checkUpdate': '檢查更新',
            
            // OTA Section
            'ota.title': 'OTA 更新',
            'ota.table.no': '序號',
            'ota.table.software': '軟體',
            'ota.table.version': '版本',
            'ota.table.upgrade': '升級',
            'ota.noUpdate': '已是最新',
            'ota.upgradeTo': '升級到',
            'ota.upgrading': '升級中...',
            
            // Software Names (package names)
            'software.thirdreality-python3': 'Python 3',
            'software.thirdreality-hacore': 'Home Assistant Core',
            'software.thirdreality-otbr-agent': 'Thread 邊界路由器',
            'software.thirdreality-zigbee-mqtt': 'Zigbee2MQTT',
            'software.thirdreality-board-firmware': '子板韌體',
            'software.thirdreality-music-assistant': '音樂助手',
            'software.thirdreality-openhab': 'OpenHAB',
            'software.thirdreality-zwave': 'Z-Wave',
            'software.thirdreality-enocean': 'EnOcean',
            'software.thirdreality-bridge': 'LinuxBox 資料路由',
            'software.linuxbox-supervisor': 'LinuxBox 管理器',
            'software.linux-image-current-meson64': 'LinuxBox 核心',
            
            // Loading & Empty States
            'loading': '載入中...',
            'loading.checkingUpdate': '檢查更新中...',
            'empty.noSystemInfo': '暫無系統資訊',
            'empty.loadFailed': '無法載入系統資訊',
            'empty.noSoftware': '沒有可更新的軟體',
            'empty.updateFailed': '無法取得更新資訊',
            
            // Progress (OTA messages from backend)
            'progress.preparing': '準備升級 {software}...',
            'progress.downloading': '正在下載 {software} v{version}...',
            'progress.downloadingSize': '下載中... {downloaded}MB / {total}MB',
            'progress.installing': '下載完成，正在安裝 {software}...',
            'progress.fixingDeps': '正在修復依賴...',
            'progress.cleaning': '正在清理...',
            'progress.complete': '{software} 升級成功！',
            'progress.upgraded': '{software} 已成功升級到 v{version}',
            'progress.downloadFailed': '下載失敗: {reason}',
            'progress.installTimeout': '安裝逾時',
            'progress.upgradeFailed': '升級失敗: {error}',
            'progress.installFailed': '安裝失敗: {error}',
            
            // Confirm Dialog
            'confirm.upgrade': '確定要將 {software} 升級到 {version} 嗎？\n\n升級過程中請勿關閉頁面或中斷裝置連接。',
            
            // Toast Messages
            'toast.connectFailed': '無法連接到裝置',
            'toast.updateFailed': '無法取得更新資訊',
            'toast.upgradeStarted': '{software} 升級已開始',
            'toast.upgradeSuccess': '{software} 升級成功！',
            'toast.upgradeFailed': '升級失敗: {error}',
            'toast.upgradeInProgress': '升級正在進行中',
            
            // System Control
            'system.control.title': '系統控制',
            'system.restart.label': '重新啟動裝置',
            'system.restart.desc': '重新啟動 LinuxBox 裝置',
            'system.restart.btn': '重新啟動',
            'system.restart.confirm': '確定要重新啟動裝置嗎？\n\n裝置將在幾分鐘內無法使用。',
            'toast.restartSuccess': '裝置正在重新啟動...',
            'toast.restartFailed': '重新啟動失敗: {error}',
            
            // Language
            'language': '語言',
        }
    },
    
    /**
     * Initialize i18n - detect browser language and load saved preference
     */
    init() {
        // Try to load saved language preference
        const savedLang = localStorage.getItem('linuxbox_lang');
        if (savedLang && this.languages[savedLang]) {
            this.currentLang = savedLang;
        } else {
            // Detect browser language
            const browserLang = navigator.language || navigator.userLanguage;
            if (browserLang.startsWith('zh')) {
                // Distinguish between Simplified and Traditional Chinese
                if (browserLang === 'zh-TW' || browserLang === 'zh-HK' || browserLang === 'zh-Hant') {
                    this.currentLang = 'zh-TW';
                } else {
                    this.currentLang = 'zh-CN';
                }
            } else {
                this.currentLang = 'en';
            }
        }
        
        return this.currentLang;
    },
    
    /**
     * Get translation for a key
     * @param {string} key - Translation key
     * @param {object} params - Optional parameters for interpolation
     * @returns {string} Translated string
     */
    t(key, params = {}) {
        const translations = this.translations[this.currentLang] || this.translations['en'];
        let text = translations[key] || this.translations['en'][key] || key;
        
        // Replace parameters
        Object.keys(params).forEach(param => {
            text = text.replace(new RegExp(`\\{${param}\\}`, 'g'), params[param]);
        });
        
        return text;
    },
    
    /**
     * Set current language
     * @param {string} lang - Language code
     */
    setLanguage(lang) {
        if (this.languages[lang]) {
            this.currentLang = lang;
            localStorage.setItem('linuxbox_lang', lang);
            return true;
        }
        return false;
    },
    
    /**
     * Get current language
     * @returns {string} Current language code
     */
    getLanguage() {
        return this.currentLang;
    },
    
    /**
     * Get all supported languages
     * @returns {object} Language code to name mapping
     */
    getLanguages() {
        return this.languages;
    },
    
    /**
     * Translate OTA progress message from backend (English) to current language
     * @param {string} message - English message from backend
     * @returns {string} Translated message
     */
    translateOtaMessage(message) {
        if (!message) return message;
        
        // Pattern matching for different message types
        const patterns = [
            // "Preparing upgrade for {software}..."
            {
                regex: /^Preparing upgrade for (.+)\.\.\.$/,
                key: 'progress.preparing',
                extract: (m) => ({ software: m[1] })
            },
            // "Downloading {software} v{version}..."
            {
                regex: /^Downloading (.+) v(.+)\.\.\.$/,
                key: 'progress.downloading',
                extract: (m) => ({ software: m[1], version: m[2] })
            },
            // "Downloading... {downloaded}MB / {total}MB"
            {
                regex: /^Downloading\.\.\. (\d+)MB \/ (\d+)MB$/,
                key: 'progress.downloadingSize',
                extract: (m) => ({ downloaded: m[1], total: m[2] })
            },
            // "Download complete, installing {software}..."
            {
                regex: /^Download complete, installing (.+)\.\.\.$/,
                key: 'progress.installing',
                extract: (m) => ({ software: m[1] })
            },
            // "Fixing dependencies..."
            {
                regex: /^Fixing dependencies\.\.\.$/,
                key: 'progress.fixingDeps',
                extract: () => ({})
            },
            // "Cleaning up..."
            {
                regex: /^Cleaning up\.\.\.$/,
                key: 'progress.cleaning',
                extract: () => ({})
            },
            // "{software} upgrade successful!"
            {
                regex: /^(.+) upgrade successful!$/,
                key: 'progress.complete',
                extract: (m) => ({ software: m[1] })
            },
            // "{software} has been upgraded to v{version}"
            {
                regex: /^(.+) has been upgraded to v(.+)$/,
                key: 'progress.upgraded',
                extract: (m) => ({ software: m[1], version: m[2] })
            },
            // "Download failed: {reason}"
            {
                regex: /^Download failed: (.+)$/,
                key: 'progress.downloadFailed',
                extract: (m) => ({ reason: m[1] })
            },
            // "Installation timed out"
            {
                regex: /^Installation timed out$/,
                key: 'progress.installTimeout',
                extract: () => ({})
            },
            // "Upgrade failed: {error}"
            {
                regex: /^Upgrade failed: (.+)$/,
                key: 'progress.upgradeFailed',
                extract: (m) => ({ error: m[1] })
            },
            // "Installation failed: {error}"
            {
                regex: /^Installation failed: (.+)$/,
                key: 'progress.installFailed',
                extract: (m) => ({ error: m[1] })
            }
        ];
        
        for (const pattern of patterns) {
            const match = message.match(pattern.regex);
            if (match) {
                const params = pattern.extract(match);
                return this.t(pattern.key, params);
            }
        }
        
        // If no pattern matches, return original message
        return message;
    }
};

// Export for use in app.js
window.I18N = I18N;

