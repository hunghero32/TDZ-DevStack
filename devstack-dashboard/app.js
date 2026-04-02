/* ============================================================
   TDZ DevStack Dashboard — Application Logic v1.0
   SPA Router + Service Management + Package Manager +
   Log Viewer + SSL + Profiles + Settings
   ============================================================ */

const API = '';
let refreshTimer = null;
let allServiceData = null;
let currentPage = 'services';

// ============================================================
// API Helper
// ============================================================
async function api(path, method = 'GET', body = null) {
    const opts = { method, headers: { 'Content-Type': 'application/json' } };
    if (body) opts.body = JSON.stringify(body);
    try {
        const res = await fetch(`${API}${path}`, opts);
        return await res.json();
    } catch (e) {
        console.error(`API Error (${path}):`, e);
        return null;
    }
}

// ============================================================
// SPA Router
// ============================================================
function navigate(page) {
    currentPage = page;
    
    // Update nav
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    const activeNav = document.querySelector(`.nav-item[data-page="${page}"]`);
    if (activeNav) activeNav.classList.add('active');
    
    // Show page
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    const activePage = document.getElementById(`page-${page}`);
    if (activePage) activePage.classList.add('active');
    
    // Update title
    const titles = {
        services: 'Services', projects: 'Projects', packages: 'Packages',
        logs: 'Logs', ssl: 'SSL Certificates', profiles: 'Profiles', settings: 'Settings'
    };
    document.getElementById('pageTitle').textContent = titles[page] || page;
    
    // Close sidebar on mobile
    document.getElementById('sidebar').classList.remove('open');
    
    // Load page data
    switch (page) {
        case 'services': refreshStatus(); break;
        case 'projects': refreshProjects(); break;
        case 'packages': refreshPackages(); break;
        case 'logs': loadLogs(); break;
        case 'ssl': loadSSL(); break;
        case 'profiles': loadProfiles(); break;
        case 'settings': loadSettings(); break;
    }
}

function toggleSidebar() {
    document.getElementById('sidebar').classList.toggle('open');
}

// Handle hash navigation
window.addEventListener('hashchange', () => {
    const hash = location.hash.slice(1);
    if (hash) navigate(hash);
});

// ============================================================
// Services Rendering
// ============================================================
function renderServices(data) {
    const grid = document.getElementById('servicesGrid');
    const serviceKeys = Object.keys(data).filter(k => !data[k].isRuntime && !data[k].isAlternate);
    
    grid.innerHTML = serviceKeys.map(key => {
        const svc = data[key];
        const isRunning = svc.running;
        return `
        <div class="service-card ${isRunning ? 'running' : ''}" style="--card-accent: ${svc.color}" id="card-${key}">
            <div class="card-header">
                <div class="card-identity">
                    <div class="card-icon">${svc.icon}</div>
                    <div>
                        <div class="card-name">${svc.name}</div>
                        ${svc.port ? `<div class="card-port clickable" onclick="openPortEditor('${key}','${svc.name}',${svc.port})" title="Click to change port">:${svc.port}</div>` : ''}
                    </div>
                </div>
                <div class="card-quick-btns">
                    <button class="icon-btn" onclick="openConfigEditorFor('${key}')" title="Edit Config">📝</button>
                    ${svc.active ? `<button class="icon-btn" onclick="quickOpen('bin/${key}/${svc.active}', 'explorer')" title="Open Folder">📂</button>` : `<button class="icon-btn" onclick="quickOpen('bin/${key}', 'explorer')" title="Open Folder">📂</button>`}
                    <div class="status-dot ${isRunning ? 'active' : ''}" title="${isRunning ? 'Running' : 'Stopped'}"></div>
                </div>
            </div>
            <div class="card-meta">
                <div class="meta-item">${shortVersion(svc.active) || 'N/A'}</div>
                ${isRunning && svc.memory ? `<div class="meta-item">💾 ${svc.memory}MB</div>` : ''}
                ${isRunning && svc.pid ? `<div class="meta-item">PID ${svc.pid}</div>` : ''}
            </div>
            <div class="card-actions">
                ${isRunning
                    ? `<button class="card-btn btn-stop-svc" onclick="controlService('${key}','stop')">■ Stop</button>
                       <button class="card-btn btn-restart" onclick="controlService('${key}','restart')">↻ Restart</button>`
                    : `<button class="card-btn btn-play" onclick="controlService('${key}','start')">▶ Start</button>`
                }
                ${svc.versions && svc.versions.length > 1
                    ? `<button class="card-btn btn-version" onclick="openVersionModal('${key}','${svc.name}')">⚙ v${shortVersion(svc.active)}</button>`
                    : ''}
            </div>
        </div>`;
    }).join('');
}

function renderRuntimes(data) {
    const grid = document.getElementById('runtimesGrid');
    const runtimeKeys = Object.keys(data).filter(k => data[k].isRuntime);
    
    grid.innerHTML = runtimeKeys.map(key => {
        const svc = data[key];
        const isPhp = key === 'php';
        return `
        <div class="runtime-card" style="--card-accent: ${svc.color}">
            <div class="runtime-header">
                <span class="runtime-icon">${svc.icon}</span>
                <span class="runtime-name">${svc.name}</span>
                ${isPhp ? `<button class="icon-btn" onclick="openPhpExtensions()" title="PHP Extensions">🧩</button>` : ''}
                ${isPhp ? `<button class="icon-btn" onclick="openConfigEditorFor('${key}')" title="Edit Config">📝</button>` : ''}
                ${svc.active ? `<button class="icon-btn" onclick="quickOpen('bin/${key}/${svc.active}', 'explorer')" title="Open Folder">📂</button>` : `<button class="icon-btn" onclick="quickOpen('bin/${key}', 'explorer')" title="Open Folder">📂</button>`}
            </div>
            <select class="runtime-version-select" onchange="switchVersion('${key}',this.value)" id="select-${key}">
                ${(svc.versions || []).map(v => `<option value="${v}" ${v === svc.active ? 'selected' : ''}>${v}</option>`).join('')}
            </select>
        </div>`;
    }).join('');
}

function shortVersion(str) {
    if (!str) return '?';
    const m = str.match(/(\d+\.\d+\.?\d*)/);
    return m ? m[1] : str.slice(0, 14);
}

// ============================================================
// Projects
// ============================================================
async function refreshProjects() {
    const projects = await api('/api/projects');
    const grid = document.getElementById('projectsGrid');
    
    if (!projects || projects.length === 0) {
        grid.innerHTML = '<p class="empty-state">No projects found in www/</p>';
        return;
    }
    
    const icons = { Laravel: '🔥', Symfony: '🎵', WordPress: '📝', PHP: '🐘', 'Node.js': '🟢', Static: '📄' };
    
    grid.innerHTML = projects.map(p => `
        <div class="project-card">
            <a href="${p.url}" target="_blank" class="project-card-main">
                <div class="project-icon-wrapper">
                    <div class="project-icon ${p.framework.toLowerCase()}">${icons[p.framework] || '📁'}</div>
                </div>
                <div class="project-info">
                    <div class="project-name">${p.name}</div>
                    <div class="project-domain">🌐 ${p.domain}</div>
                </div>
            </a>
            <div class="project-meta-row">
                ${p.phpVersion ? `<div class="project-meta">🐘 PHP ${shortVersion(p.phpVersion)}</div>` : '<div></div>'}
                <span class="project-badge ${p.framework.toLowerCase()}">${p.framework}</span>
            </div>
            <div class="project-actions-footer">
                <button onclick="quickOpen('${p.path.replace(/\\/g, '\\\\')}', 'explorer')" title="Open in File Explorer">
                    <span>📂</span> Explorer
                </button>
                <button onclick="quickOpen('${p.path.replace(/\\/g, '\\\\')}', 'code')" title="Open in VS Code">
                    <span>💻</span> VS Code
                </button>
            </div>
        </div>
    `).join('');
}

// ============================================================
// Packages
// ============================================================
async function refreshPackages() {
    const data = await api('/api/packages');
    if (!data) return;
    
    const installedGrid = document.getElementById('packagesGrid');
    const registryGrid = document.getElementById('registryGrid');
    
    // Installed packages
    if (data.installed) {
        const cats = Object.keys(data.installed).filter(c => data.installed[c].length > 0);
        if (cats.length === 0) {
            installedGrid.innerHTML = '<p class="empty-state">No packages detected</p>';
        } else {
            installedGrid.innerHTML = cats.map(cat => {
                const versions = data.installed[cat];
                const activeVersion = allServiceData && allServiceData[cat] ? allServiceData[cat].active : '';
                return `
                <div class="package-card">
                    <div class="package-header">
                        <div class="package-name">${cat.toUpperCase()}</div>
                        <span style="font-size:11px;color:var(--text-muted)">${versions.length} version(s)</span>
                    </div>
                    <div class="package-versions">
                        ${versions.map(v => {
                            const isAct = (v.name === activeVersion);
                            return `
                            <span class="package-version-tag ${isAct ? 'active' : ''}" style="display:inline-flex; align-items:center; gap:5px;">
                                ${v.name} (${v.size}MB)
                                ${!isAct ? `<span style="cursor:pointer; color:var(--danger); margin-left:3px;" onclick="removePkg('${cat}', '${v.name}')" title="Delete">&times;</span>` : ''}
                            </span>
                            `;
                        }).join('')}
                    </div>
                </div>`;
            }).join('');
        }
    }
    
    // Registry
    if (data.registry && data.registry.packages) {
        const pkgs = data.registry.packages;
        const keys = Object.keys(pkgs);
        if (keys.length === 0) {
            registryGrid.innerHTML = '<p class="empty-state">No registry data. Click "Update Registry" to fetch.</p>';
        } else {
            registryGrid.innerHTML = keys.map(cat => {
                const pkg = pkgs[cat];
                const versions = pkg.versions ? Object.keys(pkg.versions) : [];
                return versions.map(vk => {
                    const v = pkg.versions[vk];
                    return `
                    <div class="registry-item">
                        <div class="registry-info">
                            <div class="registry-name">${pkg.icon || ''} ${v.label || vk}</div>
                            <div class="registry-meta">${v.size || ''} • ${cat}</div>
                        </div>
                        <button class="btn btn-outline btn-sm" onclick="installPkg('${vk}','${v.url}','${v.extractTo}')">Install</button>
                    </div>`;
                }).join('');
            }).join('');
        }
    }
}

async function installPkg(name, url, extractTo) {
    showToast(`Installing ${name}...`, 'info');
    const r = await api('/api/packages/install', 'POST', { name, url, extractTo });
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    refreshPackages();
}

async function removePkg(category, version) {
    if (!confirm(`Delete version ${version} of ${category}?`)) return;
    showToast(`Removing ${version}...`, 'info');
    const r = await api('/api/packages/remove', 'POST', { category, version });
    if (r) showToast(r.message || 'Removed', r.success ? 'success' : 'error');
    refreshPackages();
}

async function updateRegistry() {
    showToast('Updating package registry...', 'info');
    const r = await api('/api/packages/registry/update', 'POST');
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    refreshPackages();
}

// ============================================================
// Logs
// ============================================================
async function loadLogs() {
    const service = document.getElementById('logServiceSelect').value;
    const r = await api(`/api/logs/${service}?lines=200`);
    const content = document.getElementById('logContent');
    
    if (r && r.logs && r.logs.length > 0) {
        content.textContent = r.logs.join('\n');
        // Auto-scroll to bottom
        const viewer = document.getElementById('logViewer');
        viewer.scrollTop = viewer.scrollHeight;
    } else {
        content.textContent = `No logs found for ${service}`;
    }
}

async function clearLogs() {
    const service = document.getElementById('logServiceSelect').value;
    const r = await api(`/api/logs/${service}/clear`, 'POST');
    if (r) showToast(r.message || 'Logs cleared', 'success');
    loadLogs();
}

// ============================================================
// SSL
// ============================================================
async function loadSSL() {
    const certs = await api('/api/ssl');
    const list = document.getElementById('sslList');
    
    if (!certs || certs.length === 0) {
        list.innerHTML = '<p class="empty-state">No SSL certificates generated yet. Click "Initialize CA" first, then generate certificates.</p>';
        return;
    }
    
    list.innerHTML = certs.map(c => `
        <div class="ssl-item">
            <div>
                <div class="ssl-domain">🔐 ${c.domain}</div>
                <div class="ssl-meta">Created: ${c.created} • ${c.hasKey ? '✓ Key exists' : '⚠ Missing key'}</div>
            </div>
        </div>
    `).join('');
}

async function generateSSL() {
    const domain = document.getElementById('sslDomainInput').value.trim();
    if (!domain) { showToast('Enter a domain name', 'error'); return; }
    showToast(`Generating SSL for ${domain}...`, 'info');
    const r = await api('/api/ssl/generate', 'POST', { domain });
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    loadSSL();
}

async function initCA() {
    showToast('Initializing CA...', 'info');
    const r = await api('/api/ssl/ca/init', 'POST');
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
}

// ============================================================
// Profiles
// ============================================================
async function loadProfiles() {
    const profiles = await api('/api/profiles');
    const list = document.getElementById('profilesList');
    
    if (!profiles || profiles.length === 0) {
        list.innerHTML = '<p class="empty-state">No profiles saved. Save your current configuration as a profile.</p>';
        return;
    }
    
    list.innerHTML = profiles.map(p => `
        <div class="profile-item">
            <div>
                <div class="profile-name">💾 ${p.name}</div>
                <div class="profile-meta">${p.description || 'No description'} • ${p.createdAt || ''}</div>
            </div>
            <div style="display:flex;gap:6px">
                <button class="btn btn-primary btn-sm" onclick="loadProfile('${p.name}')">Load</button>
                <button class="btn btn-danger btn-sm" onclick="deleteProfile('${p.name}')">✕</button>
            </div>
        </div>
    `).join('');
}

async function saveProfile() {
    const name = document.getElementById('profileNameInput').value.trim();
    if (!name) { showToast('Enter a profile name', 'error'); return; }
    const desc = document.getElementById('profileDescInput').value.trim();
    const r = await api('/api/profiles', 'POST', { name, description: desc });
    if (r) showToast(r.message || 'Saved', r.success ? 'success' : 'error');
    document.getElementById('profileNameInput').value = '';
    document.getElementById('profileDescInput').value = '';
    loadProfiles();
}

async function loadProfile(name) {
    showToast(`Loading profile: ${name}...`, 'info');
    const r = await api(`/api/profiles/${name}/load`, 'POST');
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    refreshStatus();
}

async function deleteProfile(name) {
    if (!confirm(`Delete profile "${name}"?`)) return;
    const r = await api(`/api/profiles/${name}`, 'DELETE');
    if (r) showToast(r.message || 'Deleted', r.success ? 'success' : 'error');
    loadProfiles();
}

// ============================================================
// Settings
// ============================================================
async function loadSettings() {
    const config = await api('/api/config');
    if (!config) return;
    
    if (config.preferences) {
        document.getElementById('settingTld').value = config.preferences.tld || '.test';
        document.getElementById('settingApiPort').value = config.preferences.apiPort || 2004;
        document.getElementById('settingAutoStart').checked = config.preferences.autoStart || false;
        document.getElementById('settingAutoVHosts').checked = config.preferences.autoVirtualHosts !== false;
    }
    
    // System info
    const info = await api('/api/info');
    if (info) {
        const grid = document.getElementById('infoGrid');
        grid.innerHTML = `
            <div class="info-row"><span class="info-label">Root</span><span class="info-value">${info.rootPath || ''}</span></div>
            <div class="info-row"><span class="info-label">Hostname</span><span class="info-value">${info.hostname || ''}</span></div>
            <div class="info-row"><span class="info-label">OS</span><span class="info-value">${info.os || ''}</span></div>
            <div class="info-row"><span class="info-label">PHP</span><span class="info-value">${info.phpVersion || ''}</span></div>
            <div class="info-row"><span class="info-label">Composer</span><span class="info-value">${info.composerVersion || ''}</span></div>
            <div class="info-row"><span class="info-label">Git</span><span class="info-value">${info.gitVersion || ''}</span></div>
            <div class="info-row"><span class="info-label">TLD</span><span class="info-value">${info.tld || ''}</span></div>
            <div class="info-row"><span class="info-label">API Port</span><span class="info-value">${info.apiPort || ''}</span></div>
            <div class="info-row"><span class="info-label">System Uptime</span><span class="info-value">${info.uptime || 0}h</span></div>
        `;
    }
}

async function saveSettings() {
    const config = await api('/api/config');
    if (!config) return;
    
    config.preferences.tld = document.getElementById('settingTld').value;
    config.preferences.apiPort = parseInt(document.getElementById('settingApiPort').value) || 2004;
    config.preferences.autoStart = document.getElementById('settingAutoStart').checked;
    config.preferences.autoVirtualHosts = document.getElementById('settingAutoVHosts').checked;
    
    const r = await api('/api/config', 'PUT', config);
    if (r) showToast(r.message || 'Settings saved', r.success ? 'success' : 'error');
}

// ============================================================
// Service Control
// ============================================================
async function controlService(name, action) {
    const card = document.getElementById(`card-${name}`);
    if (card) card.querySelectorAll('.card-btn').forEach(b => b.classList.add('loading'));
    
    const labels = { start: 'Starting', stop: 'Stopping', restart: 'Restarting' };
    showToast(`${labels[action] || action} ${name}...`, 'info');
    
    const r = await api(`/api/service/${name}/${action}`, 'POST');
    if (r) showToast(r.message || `${name} ${action} completed`, r.success ? 'success' : 'error');
    
    await refreshStatus();
}

async function controlAll(action) {
    document.getElementById('btnStartAll').disabled = true;
    document.getElementById('btnStopAll').disabled = true;
    
    showToast(`${action === 'start' ? 'Starting' : 'Stopping'} all services...`, 'info');
    const r = await api(`/api/service/all/${action}`, 'POST');
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    
    document.getElementById('btnStartAll').disabled = false;
    document.getElementById('btnStopAll').disabled = false;
    await refreshStatus();
}

// ============================================================
// Version Switching
// ============================================================
let currentModalService = null;

function openVersionModal(serviceKey, serviceName) {
    currentModalService = serviceKey;
    const svc = allServiceData[serviceKey];
    if (!svc) return;
    
    document.getElementById('modalTitle').textContent = `Switch ${serviceName} Version`;
    document.getElementById('modalBody').innerHTML = `
        <div class="version-list">
            ${(svc.versions || []).map(v => `
                <div class="version-item ${v === svc.active ? 'active' : ''}" onclick="selectVersion('${serviceKey}','${v}')">
                    <span class="version-item-name">${v}</span>
                    ${v === svc.active ? '<span class="version-item-badge">Active</span>' : ''}
                </div>
            `).join('')}
        </div>
    `;
    document.getElementById('versionModal').classList.add('active');
}

function closeModal() {
    document.getElementById('versionModal').classList.remove('active');
    currentModalService = null;
}

async function selectVersion(serviceKey, version) {
    closeModal();
    showToast(`Switching ${serviceKey} to ${version}...`, 'info');
    const r = await api('/api/version/switch', 'POST', { service: serviceKey, version });
    if (r) showToast(r.message || 'Version switched', r.success ? 'success' : 'error');
    await refreshStatus();
    await loadSystemInfo();
}

async function switchVersion(serviceKey, version) {
    showToast(`Switching ${serviceKey} to ${version}...`, 'info');
    const r = await api('/api/version/switch', 'POST', { service: serviceKey, version });
    if (r) showToast(r.message || 'Version switched', r.success ? 'success' : 'error');
    await refreshStatus();
    await loadSystemInfo();
}

// ============================================================
// PHP Info
// ============================================================
function openPhpInfo() {
    window.open('/api/phpinfo', '_blank');
}

// ============================================================
// System Info (sidebar metrics)
// ============================================================
async function loadSystemInfo() {
    const info = await api('/api/info');
    if (info) {
        const phpMatch = (info.phpVersion || '').match(/PHP\s+[\d.]+/);
        document.getElementById('metricPhp').textContent = phpMatch ? phpMatch[0] : 'PHP';
        document.getElementById('metricHost').textContent = info.hostname || '';
    }
}

// ============================================================
// Toast
// ============================================================
function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    const icons = { success: '✓', error: '✕', info: 'ℹ' };
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<span>${icons[type] || ''}</span> ${message}`;
    container.appendChild(toast);
    setTimeout(() => { toast.classList.add('toast-exit'); setTimeout(() => toast.remove(), 250); }, 3000);
}

// ============================================================
// Config Editor
// ============================================================
let configEditorFilePath = '';
let configFilesList = [];

async function openConfigEditor() {
    const modal = document.getElementById('configEditorModal');
    modal.classList.add('active');
    // Load available config files
    const files = await api('/api/configfiles');
    if (files && files.length) {
        configFilesList = files;
        const select = document.getElementById('configFileSelect');
        select.innerHTML = '<option value="">-- Select config file --</option>' +
            files.map((f, i) => `<option value="${i}">[${f.service}] ${f.label}</option>`).join('');
    }
}

async function openConfigEditorFor(service) {
    showToast(`Opening config for ${service}...`, 'info');
    const files = await api('/api/configfiles');
    if (files && files.length) {
        const idx = files.findIndex(f => f.service === service);
        if (idx >= 0) {
            const file = files[idx];
            // Open the file using the backend 'open' endpoint (which uses Start-Process / VS Code / Notepad)
            await api('/api/open', 'POST', { path: file.path, type: 'code' });
            return;
        }
    }
    showToast(`Config file for ${service} not found`, 'error');
}

async function loadSelectedConfig() {
    const select = document.getElementById('configFileSelect');
    const idx = parseInt(select.value);
    if (isNaN(idx) || !configFilesList[idx]) return;

    const file = configFilesList[idx];
    document.getElementById('configEditorArea').value = 'Loading...';
    document.getElementById('configFilePath').textContent = file.path;
    configEditorFilePath = file.path;

    const r = await api('/api/configfile/read', 'POST', { path: file.path });
    if (r && r.success) {
        document.getElementById('configEditorArea').value = r.content;
        configEditorFilePath = r.path;
        document.getElementById('configStatus').textContent = `Size: ${(r.size/1024).toFixed(1)}KB | Modified: ${r.modified}`;
    } else {
        document.getElementById('configEditorArea').value = (r && r.message) || 'Failed to load file';
        document.getElementById('configStatus').textContent = 'Error loading file';
    }
}

async function saveConfigEditor() {
    if (!configEditorFilePath) { showToast('No file selected', 'error'); return; }
    const content = document.getElementById('configEditorArea').value;
    const r = await api('/api/configfile/save', 'POST', { path: configEditorFilePath, content });
    if (r) showToast(r.message || 'Saved', r.success ? 'success' : 'error');
}

function closeConfigEditor() {
    document.getElementById('configEditorModal').classList.remove('active');
    configEditorFilePath = '';
}

// ============================================================
// PHP Extensions
// ============================================================
let phpExtData = [];

async function openPhpExtensions() {
    document.getElementById('phpExtModal').classList.add('active');
    document.getElementById('phpExtSearch').value = '';
    await loadPhpExtensions();
}

async function loadPhpExtensions() {
    const r = await api('/api/php/extensions');
    if (!r || !r.success) {
        document.getElementById('phpExtList').innerHTML = '<p class="empty-state">Failed to load extensions</p>';
        return;
    }
    phpExtData = r.extensions || [];
    document.getElementById('phpExtInfo').innerHTML = `<span class="badge">PHP ${r.phpVersion}</span> <span class="text-muted">${phpExtData.length} extensions</span>`;
    renderExtensionList(phpExtData);
}

function renderExtensionList(exts) {
    const list = document.getElementById('phpExtList');
    if (!exts.length) { list.innerHTML = '<p class="empty-state">No extensions found</p>'; return; }
    list.innerHTML = exts.map(ext => `
        <div class="ext-item">
            <label class="ext-toggle">
                <input type="checkbox" ${ext.enabled ? 'checked' : ''} onchange="toggleExtension('${ext.name}', this.checked)">
                <span class="ext-name">${ext.name}</span>
            </label>
        </div>
    `).join('');
}

function filterExtensions() {
    const q = document.getElementById('phpExtSearch').value.toLowerCase();
    const filtered = phpExtData.filter(e => e.name.toLowerCase().includes(q));
    renderExtensionList(filtered);
}

async function toggleExtension(name, enabled) {
    const r = await api('/api/php/extensions', 'POST', { name, enabled });
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    await loadPhpExtensions();
}

function closePhpExtModal() {
    document.getElementById('phpExtModal').classList.remove('active');
}

// ============================================================
// Port Editor
// ============================================================
let portEditorService = '';

function openPortEditor(service, name, currentPort) {
    portEditorService = service;
    document.getElementById('portServiceLabel').textContent = name;
    document.getElementById('portInput').value = currentPort;
    document.getElementById('portEditorTitle').textContent = `🔌 ${name} Port`;
    document.getElementById('portEditorModal').classList.add('active');
    document.getElementById('portInput').focus();
}

async function savePort() {
    const port = parseInt(document.getElementById('portInput').value);
    if (!port || port < 1 || port > 65535) { showToast('Invalid port', 'error'); return; }
    const r = await api('/api/port/set', 'POST', { service: portEditorService, port });
    if (r) showToast(r.message || 'Done', r.success ? 'success' : 'error');
    closePortEditor();
    await refreshStatus();
}

function closePortEditor() {
    document.getElementById('portEditorModal').classList.remove('active');
    portEditorService = '';
}

// ============================================================
// Quick Open
// ============================================================
async function quickOpen(path, type) {
    const r = await api('/api/open', 'POST', { path, type: type || 'explorer' });
    if (r && !r.success) showToast(r.message || 'Failed', 'error');
}

// ============================================================
// Status Refresh
// ============================================================
async function refreshStatus() {
    const data = await api('/api/status');
    if (!data) {
        showToast('Cannot connect to TDZ DevStack API', 'error');
        return;
    }
    allServiceData = data;
    renderServices(data);
    renderRuntimes(data);
}

// ============================================================
// Init
// ============================================================
async function init() {
    await refreshStatus();
    await refreshProjects();
    await loadSystemInfo();
    
    // Handle initial hash
    const hash = location.hash.slice(1);
    if (hash) navigate(hash);
    
    // Auto-refresh every 5 seconds
    refreshTimer = setInterval(() => {
        if (currentPage === 'services') refreshStatus();
    }, 15000);
}

// Event: Modal overlay clicks
['versionModal','configEditorModal','phpExtModal','portEditorModal'].forEach(id => {
    document.getElementById(id).addEventListener('click', function(e) {
        if (e.target === this) {
            this.classList.remove('active');
        }
    });
});

// Event: Escape key
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
        closeModal();
        closeConfigEditor();
        closePhpExtModal();
        closePortEditor();
    }
});

// Start
init();
