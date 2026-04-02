const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');
const os = require('os');

// ============================================================
// TDZ DevStack API Server v1.0 (Node.js version)
// ============================================================

const rootDir = process.env.TDZ_ROOT || path.resolve(__dirname, '..');
if (!fs.existsSync(path.join(rootDir, 'usr'))) {
    console.error('ERROR: Invalid TDZ root:', rootDir);
    process.exit(1);
}

// Global state
let config = getDefaultConfig();
let apiPort = 8080;

// Load Config
function loadConfig() {
    const configPath = path.join(rootDir, 'usr', 'tdz.json');
    if (fs.existsSync(configPath)) {
        try {
            let content = fs.readFileSync(configPath, 'utf8');
            if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);
            config = JSON.parse(content);
            if (config.preferences && config.preferences.apiPort) {
                apiPort = config.preferences.apiPort;
            }
        } catch (e) {
            console.warn('Failed to parse tdz.json:', e.message);
        }
    }
}

function saveConfig(newConfig) {
    fs.writeFileSync(path.join(rootDir, 'usr', 'tdz.json'), JSON.stringify(newConfig, null, 4), 'utf8');
    config = newConfig;
}

function getDefaultConfig() {
    return {
        version: "1.0.0",
        name: "TDZ DevStack",
        preferences: { autoStart: false, autoVirtualHosts: true, tld: ".test", language: "vi", theme: "dark", apiPort: 8080, dashboardAutoOpen: true, logLevel: "info" },
        services: {
            apache: { active: "", autoStart: true, port: 80, sslPort: 443 },
            mysql: { active: "", autoStart: true, port: 3306, rootPassword: "" },
            redis: { active: "", autoStart: true, port: 6379 },
            memcached: { active: "", autoStart: true, port: 11211 },
            mailpit: { active: "mailpit", autoStart: true, smtpPort: 1025, uiPort: 8025 },
            nginx: { active: "", autoStart: false, port: 80, isAlternate: true }
        },
        runtimes: { php: { active: "" }, nodejs: { active: "" }, python: { active: "" } },
        packages: { registryUrl: "https://raw.githubusercontent.com/tdz-devstack/registry/main/packages.json", sourcesFile: "packages.conf" }
    };
}

// Fast Tasklist parsing
function getRunningProcesses() {
    try {
        const out = execSync('tasklist /NH /FO CSV', { encoding: 'utf8', windowsHide: true });
        const procs = {};
        out.split('\n').forEach(line => {
            if (!line.trim()) return;
            const parts = line.split('","');
            if (parts.length >= 5) {
                const name = parts[0].replace('"', '').toLowerCase();
                const pid = parseInt(parts[1], 10);
                const mem = parseInt(parts[4].replace(/[^\d]/g, ''), 10) || 0; // KB
                if (!procs[name]) procs[name] = [];
                procs[name].push({ pid, mem });
            }
        });
        return procs;
    } catch { return {}; }
}

function getServiceProcessName(svc) {
    const map = { apache: 'httpd.exe', mysql: 'mysqld.exe', redis: 'redis-server.exe', mailpit: 'mailpit.exe', memcached: 'memcached.exe', nginx: 'nginx.exe' };
    return map[svc] || `${svc}.exe`;
}

function getServiceDisplayInfo(svc) {
    const map = {
        apache: { name: "Apache", icon: "W", color: "#E44D26" },
        mysql: { name: "MySQL", icon: "D", color: "#4479A1" },
        redis: { name: "Redis", icon: "R", color: "#DC382D" },
        mailpit: { name: "Mailpit", icon: "M", color: "#00B4D8" },
        memcached: { name: "Memcached", icon: "C", color: "#6DB33F" },
        nginx: { name: "Nginx", icon: "N", color: "#009639" },
        php: { name: "PHP", icon: "P", color: "#777BB4" },
        nodejs: { name: "Node.js", icon: "J", color: "#339933" },
        python: { name: "Python", icon: "Y", color: "#3776AB" }
    };
    return map[svc] || { name: svc, icon: "?", color: "#888" };
}

function getInstalledVersions(category) {
    const dir = path.join(rootDir, 'bin', category);
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name);
}

function getServiceMeta() {
    loadConfig();
    const result = {};
    const services = ['apache', 'mysql', 'redis', 'mailpit', 'memcached', 'nginx'];
    services.forEach(svc => {
        const info = getServiceDisplayInfo(svc);
        result[svc] = {
            name: info.name,
            processName: getServiceProcessName(svc),
            icon: info.icon, color: info.color,
            port: config.services[svc]?.port,
            active: config.services[svc]?.active || '',
            autoStart: !!config.services[svc]?.autoStart,
            versions: getInstalledVersions(svc),
            isRuntime: false, isAlternate: svc === 'nginx'
        };
    });
    const runtimes = ['php', 'nodejs', 'python'];
    runtimes.forEach(rt => {
        const info = getServiceDisplayInfo(rt);
        result[rt] = {
            name: info.name, icon: info.icon, color: info.color,
            active: config.runtimes[rt]?.active || '',
            versions: getInstalledVersions(rt),
            isRuntime: true, isAlternate: false
        };
    });
    return result;
}

function getAllStatus() {
    const meta = getServiceMeta();
    const runningProcs = getRunningProcesses();
    const result = {};
    for (const key in meta) {
        const svc = meta[key];
        const status = { running: false, pid: [], memory: 0 };
        if (svc.processName && runningProcs[svc.processName]) {
            status.running = true;
            status.pid = runningProcs[svc.processName].map(p => p.pid);
            status.memory = Math.round(runningProcs[svc.processName].reduce((s, p) => s + p.mem, 0) / 1024 * 10) / 10;
        }
        result[key] = {
            ...svc,
            running: status.running,
            pid: status.pid[0] || null,
            memory: status.memory
        };
    }
    return result;
}

// Process Control
function writeLog(service, message, level = "INFO") {
    const logDir = path.join(rootDir, 'logs');
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir);
    const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
    const line = `[${ts}] [${level}] [${service}] ${message}\n`;
    fs.appendFileSync(path.join(logDir, 'tdz.log'), line);
    if (service !== 'system') {
        const svcDir = path.join(logDir, service);
        if (!fs.existsSync(svcDir)) fs.mkdirSync(svcDir);
        fs.appendFileSync(path.join(svcDir, `${service}.log`), line);
    }
    console.log(line.trim());
}

function getServiceExePath(svc, version) {
    const bin = path.join(rootDir, 'bin');
    const map = {
        apache: path.join(bin, `apache/${version}/bin/httpd.exe`),
        mysql: path.join(bin, `mysql/${version}/bin/mysqld.exe`),
        redis: path.join(bin, `redis/${version}/redis-server.exe`),
        mailpit: path.join(bin, `mailpit/${version}/mailpit.exe`),
        memcached: path.join(bin, `memcached/${version}/memcached.exe`),
        nginx: path.join(bin, `nginx/${version}/nginx.exe`)
    };
    return map[svc] || '';
}

function getServiceArgs(svc, version) {
    switch (svc) {
        case 'apache': {
            const httpdConf = path.join(rootDir, 'bin', 'apache', version, 'conf', 'httpd.conf');
            if (fs.existsSync(httpdConf)) return ['-f', httpdConf];
            return [];
        }
        case 'mysql': {
            const myIni = path.join(rootDir, 'bin', 'mysql', version, 'my.ini');
            const arr = [`--port=${config.services.mysql.port}`];
            if (fs.existsSync(myIni)) arr.unshift(`--defaults-file=${myIni}`);
            return arr;
        }
        case 'memcached': return ['-m', '64', '-p', config.services.memcached.port.toString()];
        case 'nginx': return ['-p', path.join(rootDir, `bin/nginx/${version}`)];
        default: return [];
    }
}

function startService(svcKey) {
    const meta = getServiceMeta()[svcKey];
    if (!meta) return { success: false, message: `Unknown service: ${svcKey}` };
    if (meta.isRuntime) return { success: false, message: `${meta.name} is a runtime` };
    
    const runningProcs = getRunningProcesses();
    if (runningProcs[meta.processName]) return { success: true, message: `${meta.name} already running` };

    const exe = getServiceExePath(svcKey, meta.active);
    if (!fs.existsSync(exe)) return { success: false, message: `Binary not found: ${exe}` };

    const args = getServiceArgs(svcKey, meta.active);
    try {
        if (svcKey === 'apache' && config.preferences?.autoVirtualHosts !== false) {
            updateVirtualHosts();
        }
        writeLog(svcKey, `Starting ${meta.name}...`);
        const proc = spawn(exe, args, { detached: true, stdio: 'ignore', windowsHide: true, cwd: path.dirname(exe) });
        proc.unref();
        writeLog(svcKey, `${meta.name} started (PID ${proc.pid})`);
        return { success: true, message: `${meta.name} started` };
    } catch (e) {
        writeLog(svcKey, `Error: ${e.message}`, "ERROR");
        return { success: false, message: e.message };
    }
}

function stopService(svcKey) {
    const meta = getServiceMeta()[svcKey];
    if (!meta || !meta.processName) return { success: false, message: "Unknown service" };
    
    writeLog(svcKey, `Stopping ${meta.name}...`);
    
    // Graceful
    if (svcKey === 'apache') {
        const exe = getServiceExePath(svcKey, meta.active);
        if (fs.existsSync(exe)) try { execSync(`"${exe}" -k stop`, { windowsHide: true }); } catch {}
    } else if (svcKey === 'mysql') {
        const exe = path.join(rootDir, `bin/mysql/${meta.active}/bin/mysqladmin.exe`);
        if (fs.existsSync(exe)) try { execSync(`"${exe}" -u root shutdown`, { windowsHide: true }); } catch {}
    }

    // Force kill
    try { execSync(`taskkill /IM ${meta.processName} /F`, { windowsHide: true, stdio: 'ignore' }); } catch {}
    
    writeLog(svcKey, `${meta.name} stopped`);
    return { success: true, message: `${meta.name} stopped` };
}

// Fallback to powershell for complex scripts
function runPsModule(command) {
    try {
        const script = `
        $ErrorActionPreference = 'SilentlyContinue';
        $Root = '${rootDir.replace(/\\/g, '\\\\')}';
        $modulesDir = Join-Path $Root 'bin\\tdz\\modules';
        foreach ($m in Get-ChildItem $modulesDir -Filter '*.ps1') { . $m.FullName };
        ${command}
        `;
        const out = execSync(`powershell -ExecutionPolicy Bypass -NoProfile -Command "${script.replace(/\n/g, ' ').replace(/"/g, '\\"')}"`, { encoding: 'utf8', windowsHide: true });
        console.log('[runPsModule] script:', script);
        console.log('[runPsModule] out:', out);
        try {
            const lines = out.trim().split('\n');
            const lastLine = lines[lines.length - 1];
            return JSON.parse(lastLine);
        } catch {
            return { success: true, psOutput: out };
        }
    } catch (e) {
        return { success: false, message: e.message };
    }
}

function updateVirtualHosts() {
    loadConfig();
    const wwwDir = path.join(rootDir, 'www');
    const sitesDir = path.join(rootDir, 'etc', 'apache2', 'sites-enabled');
    const nginxSitesDir = path.join(rootDir, 'etc', 'nginx', 'sites-enabled');
    const tld = config.preferences.tld || '.test';
    const hostsFile = 'C:\\Windows\\System32\\drivers\\etc\\hosts';
    
    if (!fs.existsSync(sitesDir)) fs.mkdirSync(sitesDir, { recursive: true });
    if (!fs.existsSync(nginxSitesDir)) fs.mkdirSync(nginxSitesDir, { recursive: true });
    if (!fs.existsSync(wwwDir)) return { success: true, message: "No www directory" };
    
    let created = 0;
    let hostsEntries = [];
    
    const projects = fs.readdirSync(wwwDir, { withFileTypes: true }).filter(d => d.isDirectory());
    for (const project of projects) {
        const projectName = project.name;
        const domain = `${projectName}${tld}`;
        const confFile = path.join(sitesDir, `auto.${domain}.conf`);
        
        let docRoot = path.join(wwwDir, projectName);
        if (fs.existsSync(path.join(docRoot, 'public'))) docRoot = path.join(docRoot, 'public');
        const docRootUnix = docRoot.replace(/\\/g, '/');
        
        // Apache config
        if (!fs.existsSync(confFile)) {
            const port = config.services.apache?.port || 80;
            const vhost = `# Auto-generated by TDZ DevStack for: ${projectName}\n<VirtualHost *:${port}>\n    DocumentRoot "${docRootUnix}"\n    ServerName ${domain}\n    ServerAlias *.${domain}\n    <Directory "${docRootUnix}">\n        AllowOverride All\n        Require all granted\n    </Directory>\n</VirtualHost>`;
            fs.writeFileSync(confFile, vhost, 'utf8');
            created++;
            writeLog('vhost', `Created vhost: ${domain} -> ${docRootUnix}`);
        }
        
        // Nginx config
        const nConfFile = path.join(nginxSitesDir, `auto.${domain}.conf`);
        if (!fs.existsSync(nConfFile)) {
            const nPort = config.services.nginx?.port || 80;
            const nvhost = `# Auto-generated by TDZ DevStack\nserver {\n    listen ${nPort};\n    server_name ${domain} *.${domain};\n    root "${docRootUnix}";\n    index index.php index.html;\n    location / { try_files $uri $uri/ /index.php?$query_string; }\n    location ~ \\.php$ {\n        fastcgi_pass 127.0.0.1:2004;\n        fastcgi_index index.php;\n        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n        include fastcgi_params;\n    }\n}`;
            fs.writeFileSync(nConfFile, nvhost, 'utf8');
        }
        
        hostsEntries.push(`127.0.0.1\t${domain}`);
    }
    
    // Update Hosts
    try {
        let hostsContent = fs.existsSync(hostsFile) ? fs.readFileSync(hostsFile, 'utf8') : '';
        let changed = false;
        for (const entry of hostsEntries) {
            const domain = entry.split('\t')[1];
            const regex = new RegExp(`^[\\s\\d.]+\\s+${domain.replace(/\\./g, '\\\\.')}\\s*$`, 'm');
            if (!regex.test(hostsContent)) {
                hostsContent += `\r\n${entry}`;
                changed = true;
            }
        }
        if (changed) {
            fs.writeFileSync(hostsFile, hostsContent, 'utf8');
            writeLog('vhost', `Updated hosts file with ${hostsEntries.length} entries`);
        }
        return { success: true, message: `Virtual hosts updated (${created} new configs)` };
    } catch {
        return { success: true, message: `VHost configs updated (${created} new configs). Hosts file requires admin rights.` };
    }
}

function switchVersion(service, newVersion) {
    console.log(`[API] switchVersion called with: service='${service}', newVersion='${newVersion}'`);
    loadConfig();
    const meta = getServiceMeta();
    console.log(`[API] meta[${service}]:`, meta[service]);
    if (!meta[service] || !meta[service].versions.includes(newVersion)) {
        return { success: false, message: "Invalid version" };
    }
    
    // Stop service gracefully
    stopService(service);
    if (service === 'php') { stopService('apache'); stopService('nginx'); }
    
    // Save to config
    if (meta[service].isRuntime) config.runtimes[service].active = newVersion;
    else config.services[service].active = newVersion;
    saveConfig(config);
    
    // Handle PHP specific Apache logic
    if (service === 'php') {
        const httpdConfPath = path.join(rootDir, 'etc', 'apache2', 'httpd.conf');
        if (fs.existsSync(httpdConfPath)) {
            let conf = fs.readFileSync(httpdConfPath, 'utf8');
            const newDll = path.join(rootDir, `bin/php/${newVersion}/php8apache2_4.dll`).replace(/\\/g, '/');
            const newIni = path.join(rootDir, `bin/php/${newVersion}`).replace(/\\/g, '/');
            conf = conf.replace(/LoadModule php_module ".*?php8apache2_4\.dll"/gi, `LoadModule php_module "${newDll}"`);
            conf = conf.replace(/PHPIniDir ".*?"/gi, `PHPIniDir "${newIni}"`);
            fs.writeFileSync(httpdConfPath, conf, 'utf8');
        }
    }
    
    return { success: true, message: `${meta[service].name} switched to ${newVersion}` };
}


// HTTP SERVER
const mimeTypes = {
    '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript', 
    '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', 
    '.ico': 'image/x-icon', '.svg': 'image/svg+xml'
};

const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') { res.writeHead(200); res.end(); return; }

    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;

    let body = [];
    req.on('data', chunk => body.push(chunk));
    req.on('end', () => {
        body = Buffer.concat(body).toString();
        console.log(`[API] Raw Body: '${body}'`);
        let json = {};
        if (body) try { json = JSON.parse(body); } catch {}
        console.log(`[API] ${req.method} ${pathname} | body:`, json);

        function sendJson(data, status = 200) {
            res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(JSON.stringify(data));
        }

        // --- API ROUTES ---
        if (pathname.startsWith('/api/')) {
            loadConfig();
            
            if (pathname === '/api/status') return sendJson(getAllStatus());
            if (pathname === '/api/health') return sendJson({ status: 'ok', version: '1.0.0', uptime: Math.round(process.uptime() / 60) });
            if (pathname === '/api/info') return sendJson({ 
                hostname: os.hostname(), os: os.release(), rootPath: rootDir, tld: config.preferences.tld, apiPort
            });
            if (pathname === '/api/config') {
                if (req.method === 'GET') return sendJson(config);
                if (req.method === 'PUT') { saveConfig(json); return sendJson({ success: true }); }
            }
            if (pathname === '/api/service/all/start') {
                ['apache','mysql','redis','mailpit','memcached'].forEach(s => { if(config.services[s]?.autoStart) startService(s); });
                return sendJson({ success: true, message: "Services started" });
            }
            if (pathname === '/api/service/all/stop') {
                ['memcached','mailpit','redis','mysql','apache','nginx'].forEach(stopService);
                return sendJson({ success: true, message: "All services stopped" });
            }
            
            const svcAction = pathname.match(/^\/api\/service\/(\w+)\/(start|stop|restart)$/);
            if (svcAction) {
                const [, svc, action] = svcAction;
                if (action === 'start') return sendJson(startService(svc));
                if (action === 'stop') return sendJson(stopService(svc));
                if (action === 'restart') { stopService(svc); setTimeout(() => sendJson(startService(svc)), 1000); return; }
            }

            if (pathname === '/api/open') {
                const target = path.isAbsolute(json.path) ? json.path : path.join(rootDir, json.path);
                if (json.type === 'code') {
                    try { execSync(`code "${target}"`, { windowsHide: true }); } 
                    catch { execSync(`notepad.exe "${target}"`, { windowsHide: true }); }
                } else {
                    execSync(`explorer.exe "${target}"`, { windowsHide: true });
                }
                return sendJson({ success: true, message: "Opened" });
            }

            // --- NATIVE NODE.JS ENDPOINTS ---
            // PROJECTS
            if (pathname === '/api/projects') {
                const wwwDir = path.join(rootDir, 'www');
                let projects = [];
                if (fs.existsSync(wwwDir)) {
                    const dirs = fs.readdirSync(wwwDir, { withFileTypes: true }).filter(d => d.isDirectory());
                    for (const d of dirs) {
                        const projName = d.name;
                        const projDomain = projName + config.preferences.tld;
                        const projPath = path.join(wwwDir, projName);
                        const hasPublic = fs.existsSync(path.join(projPath, 'public'));
                        const hasTdzConfig = fs.existsSync(path.join(projPath, '.tdz.json'));
                        
                        let framework = 'Static';
                        if (fs.existsSync(path.join(projPath, 'composer.json'))) {
                            try {
                                const cj = JSON.parse(fs.readFileSync(path.join(projPath, 'composer.json')));
                                if (cj.require && cj.require['laravel/framework']) framework = 'Laravel';
                                else if (cj.require && cj.require['symfony/framework-bundle']) framework = 'Symfony';
                                else if (fs.existsSync(path.join(projPath, 'wp-config.php'))) framework = 'WordPress';
                                else framework = 'PHP';
                            } catch { framework = 'PHP'; }
                        } else if (fs.existsSync(path.join(projPath, 'package.json'))) {
                            framework = 'Node.js';
                        } else if (fs.existsSync(path.join(projPath, 'wp-config.php'))) {
                            framework = 'WordPress';
                        }
                        
                        let phpVersion = null, nodeVersion = null;
                        if (hasTdzConfig) {
                            try {
                                let c = fs.readFileSync(path.join(projPath, '.tdz.json'), 'utf8');
                                if (c.charCodeAt(0) === 0xFEFF) c = c.slice(1);
                                const pCfg = JSON.parse(c);
                                phpVersion = pCfg.php || null;
                                nodeVersion = pCfg.node || null;
                            } catch {}
                        }
                        projects.push({ name: projName, domain: projDomain, url: `http://${projDomain}`, path: projPath, framework, hasPublic, hasTdzConfig, phpVersion, nodeVersion });
                    }
                }
                return sendJson(projects);
            }
            
            const projConfigMatch = pathname.match(/^\/api\/projects\/([^/]+)\/config$/);
            if (projConfigMatch) {
                const projName = projConfigMatch[1];
                const cfgPath = path.join(rootDir, 'www', projName, '.tdz.json');
                if (req.method === 'GET') {
                    if (fs.existsSync(cfgPath)) {
                        try {
                            let c = fs.readFileSync(cfgPath, 'utf8');
                            if (c.charCodeAt(0) === 0xFEFF) c = c.slice(1);
                            return sendJson(JSON.parse(c));
                        } catch { return sendJson({ error: "Invalid JSON" }); }
                    } else return sendJson({ message: "No .tdz.json found" });
                }
                if (req.method === 'PUT') {
                    fs.writeFileSync(cfgPath, JSON.stringify(json, null, 4), 'utf8');
                    return sendJson({ success: true, message: "Project config saved" });
                }
            }

            // LOGS
            if (pathname === '/api/logs') {
                const logDir = path.join(rootDir, 'logs');
                let logs = [];
                if (fs.existsSync(logDir)) logs.push({ name: 'system', path: path.join(logDir, 'tdz.log'), size: fs.existsSync(path.join(logDir, 'tdz.log')) ? Math.round(fs.statSync(path.join(logDir, 'tdz.log')).size/1024) : 0, modified: '' });
                const services = ['apache', 'mysql', 'redis', 'mailpit', 'memcached', 'nginx'];
                services.forEach(s => {
                    const lf = path.join(logDir, s, `${s}.log`);
                    if (fs.existsSync(lf)) logs.push({ name: s, path: lf, size: Math.round(fs.statSync(lf).size/1024), modified: '' });
                });
                return sendJson(logs);
            }
            const logSvcMatch = pathname.match(/^\/api\/logs\/([^/]+)$/);
            if (logSvcMatch && req.method === 'GET') {
                const svc = logSvcMatch[1];
                const lf = (svc === 'system' || svc === 'all') 
                    ? path.join(rootDir, 'logs', 'tdz.log') 
                    : path.join(rootDir, 'logs', svc, `${svc}.log`);
                
                if (!fs.existsSync(lf)) {
                    return sendJson({ service: svc, logs: [`No logs found for ${svc}`] });
                }

                let content = "";
                const stats = fs.statSync(lf);
                const maxSize = 2 * 1024 * 1024; // 2MB
                if (stats.size > maxSize) {
                    const buffer = Buffer.alloc(maxSize);
                    const fd = fs.openSync(lf, 'r');
                    fs.readSync(fd, buffer, 0, maxSize, stats.size - maxSize);
                    fs.closeSync(fd);
                    content = buffer.toString('utf8');
                } else {
                    content = fs.readFileSync(lf, 'utf8');
                }

                const lines = content.split(/\r?\n/).filter(Boolean);
                const linesLimit = parseInt(url.searchParams.get('lines')) || 100;
                return sendJson({ service: svc, success: true, logs: lines.slice(-linesLimit) });
            }
            
            const logClearMatch = pathname.match(/^\/api\/logs\/([^/]+)\/clear$/);
            if (logClearMatch && req.method === 'POST') {
                const svc = logClearMatch[1];
                const lf = (svc === 'system' || svc === 'all') 
                    ? path.join(rootDir, 'logs', 'tdz.log') 
                    : path.join(rootDir, 'logs', svc, `${svc}.log`);
                if (fs.existsSync(lf)) fs.writeFileSync(lf, '');
                return sendJson({ success: true, message: `Logs cleared for ${svc}` });
            }

            // PROFILES
            if (pathname === '/api/profiles') {
                const pDir = path.join(rootDir, 'etc', 'profiles');
                let profs = [];
                if (fs.existsSync(pDir)) {
                    fs.readdirSync(pDir, { withFileTypes: true }).filter(d => d.isDirectory()).forEach(d => {
                        try {
                            const meta = JSON.parse(fs.readFileSync(path.join(pDir, d.name, 'meta.json')));
                            profs.push(meta);
                        } catch { profs.push({ name: d.name, description: "Unknown" }); }
                    });
                }
                if (req.method === 'GET') return sendJson(profs);
                if (req.method === 'POST') {
                    const tgt = path.join(pDir, json.name);
                    if (!fs.existsSync(tgt)) fs.mkdirSync(tgt, { recursive: true });
                    fs.cpSync(path.join(rootDir, 'usr'), path.join(tgt, 'usr'), { recursive: true });
                    fs.writeFileSync(path.join(tgt, 'meta.json'), JSON.stringify({ name: json.name, description: json.description || '', createdAt: new Date().toISOString() }));
                    return sendJson({ success: true, message: "Profile saved" });
                }
            }
            const profLoadMatch = pathname.match(/^\/api\/profiles\/([^/]+)\/load$/);
            if (profLoadMatch) {
                const src = path.join(rootDir, 'etc', 'profiles', profLoadMatch[1], 'usr');
                if (fs.existsSync(src)) {
                    fs.cpSync(src, path.join(rootDir, 'usr'), { recursive: true, force: true });
                    return sendJson({ success: true });
                }
                return sendJson({ success: false });
            }
            const profDelMatch = pathname.match(/^\/api\/profiles\/([^/]+)$/);
            if (profDelMatch && req.method === 'DELETE') {
                const tgt = path.join(rootDir, 'etc', 'profiles', profDelMatch[1]);
                if (fs.existsSync(tgt)) fs.rmSync(tgt, { recursive: true, force: true });
                return sendJson({ success: true });
            }

            // SSL
            if (pathname === '/api/ssl' && req.method === 'GET') {
                const sslDir = path.join(rootDir, 'etc', 'ssl', 'certs');
                let certs = [];
                if (fs.existsSync(sslDir)) {
                    fs.readdirSync(sslDir).filter(f => f.endsWith('.crt')).forEach(f => {
                        certs.push({ domain: f.replace('.crt', ''), expires: 'Unknown', issued: 'Unknown' });
                    });
                }
                return sendJson(certs);
            }

            // CONFIG FILES (Settings editor)
            if (pathname === '/api/configfiles') {
                return sendJson(runPsModule('ConvertTo-Json -InputObject (Get-AvailableConfigFiles -RootDir $Root) -Compress -Depth 10'));
            }
            if (pathname === '/api/configfile/read' && req.method === 'POST') {
                if (fs.existsSync(json.path)) {
                    let c = fs.readFileSync(json.path, 'utf8');
                    return sendJson({ success: true, path: json.path, content: c, size: c.length });
                }
                return sendJson({ success: false, message: "File not found" });
            }
            if (pathname === '/api/configfile/save' && req.method === 'POST') {
                if (json.path && json.content) {
                    fs.writeFileSync(json.path, json.content, 'utf8');
                    return sendJson({ success: true });
                }
            }

            // SHUTDOWN
            if (pathname === '/api/shutdown' && req.method === 'POST') {
                writeLog('system', 'Shutdown requested via API. Closing server...');
                sendJson({ success: true, message: 'Shutting down...' });
                setTimeout(() => process.exit(0), 500);
                return;
            }

            // PACKAGES
            if (pathname === '/api/packages' && req.method === 'GET') {
                const regPath = path.join(rootDir, 'bin', 'tdz', 'registry', 'packages.json');
                let registry = {};
                try { if (fs.existsSync(regPath)) registry = JSON.parse(fs.readFileSync(regPath, 'utf8')); } catch {}
                
                let installed = {};
                const cats = ['php', 'nodejs', 'python', 'apache', 'nginx', 'mysql', 'redis', 'memcached', 'mailpit'];
                cats.forEach(c => {
                    const cDir = path.join(rootDir, 'bin', c);
                    installed[c] = [];
                    if (fs.existsSync(cDir)) {
                        fs.readdirSync(cDir, { withFileTypes: true }).filter(d => d.isDirectory()).forEach(d => {
                            installed[c].push({ name: d.name, size: 0 }); // Size omitted for speed
                        });
                    }
                });
                return sendJson({ registry, installed });
            }

            // FALLBACK TO POWERSHELL FOR HEAVY/COMPLEX/RARE OPS
            if (pathname === '/api/vhosts/update') return sendJson(updateVirtualHosts());
            if (pathname === '/api/vhosts') return sendJson(runPsModule('Get-VirtualHosts -RootDir $Root | ConvertTo-Json -Compress'));
            if (pathname === '/api/ssl/generate') return sendJson(runPsModule(`New-SSLCertificate -RootDir $Root -Domain '${json.domain}' | ConvertTo-Json -Compress`));
            if (pathname === '/api/ssl/ca/init') return sendJson(runPsModule(`Initialize-SSLCA -RootDir $Root | ConvertTo-Json -Compress`));
            if (pathname === '/api/version/switch') return sendJson(switchVersion(json.service, json.version));
            if (pathname === '/api/version/available') return sendJson(runPsModule('ConvertTo-Json -InputObject (Get-AllVersionInfo -RootDir $Root) -Compress -Depth 10'));
            if (pathname === '/api/packages/install') return sendJson(runPsModule(`ConvertTo-Json -InputObject (Install-Package -RootDir $Root -PackageName '${json.name || ''}' -Url '${json.url || ''}' -ExtractTo '${json.extractTo || ''}') -Compress -Depth 10`));
            if (pathname === '/api/packages/remove') {
                const category = json.category;
                const version = json.version;
                if (!category || !version) return sendJson({ success: false, message: 'Missing parameters' });
                const tgt = path.join(rootDir, 'bin', category, version);
                
                loadConfig();
                if ((config.services[category] && config.services[category].active === version) ||
                    (config.runtimes[category] && config.runtimes[category].active === version)) {
                    return sendJson({ success: false, message: `Cannot remove active version '${version}'. Switch to another version first.` });
                }
                
                if (fs.existsSync(tgt)) {
                    try {
                        fs.rmSync(tgt, { recursive: true, force: true });
                        writeLog('package', `Removed ${category}/${version}`);
                        return sendJson({ success: true, message: `Removed ${category}/${version}` });
                    } catch(e) {
                        return sendJson({ success: false, message: e.message });
                    }
                }
                return sendJson({ success: false, message: 'Package not found: ' + tgt });
            }
            if (pathname === '/api/php/extensions') {
                // Native Node.js implementation — avoids PowerShell serialization crashes
                const phpVer = config.runtimes?.php?.active || '';
                const phpIni = path.join(rootDir, 'bin', 'php', phpVer, 'php.ini');

                if (!fs.existsSync(phpIni)) {
                    return sendJson({ success: false, message: 'php.ini not found', extensions: [], phpVersion: phpVer });
                }

                if (req.method === 'GET') {
                    try {
                        const content = fs.readFileSync(phpIni, 'utf8');
                        const lines = content.split(/\r?\n/);
                        const extensions = [];
                        lines.forEach((line, idx) => {
                            const trimmed = line.trim();
                            const match = trimmed.match(/^(;)?\s*extension\s*=\s*(.+)$/);
                            if (match) {
                                extensions.push({
                                    name: match[2].trim(),
                                    enabled: !match[1], // no semicolon = enabled
                                    line: idx + 1
                                });
                            }
                        });
                        return sendJson({ success: true, phpVersion: phpVer, iniPath: phpIni, extensions });
                    } catch (e) {
                        return sendJson({ success: false, message: e.message, extensions: [], phpVersion: phpVer });
                    }
                }

                if (req.method === 'POST') {
                    try {
                        const extName = json.name;
                        const enabled = !!json.enabled;

                        // Backup
                        try { fs.copyFileSync(phpIni, phpIni + '.bak'); } catch {}

                        const content = fs.readFileSync(phpIni, 'utf8');
                        const lines = content.split(/\r?\n/);
                        let found = false;
                        const newLines = lines.map(line => {
                            const trimmed = line.trim();
                            const match = trimmed.match(/^;?\s*extension\s*=\s*(.+)$/);
                            if (match && match[1].trim() === extName) {
                                found = true;
                                return enabled ? `extension=${extName}` : `;extension=${extName}`;
                            }
                            return line;
                        });

                        if (!found) {
                            return sendJson({ success: false, message: `Extension '${extName}' not found in php.ini` });
                        }

                        fs.writeFileSync(phpIni, newLines.join('\r\n'), 'utf8');
                        const action = enabled ? 'enabled' : 'disabled';
                        writeLog('php', `Extension ${extName} ${action}`);
                        return sendJson({ success: true, message: `Extension ${extName} ${action}` });
                    } catch (e) {
                        return sendJson({ success: false, message: e.message });
                    }
                }
            }
            if (pathname === '/api/port/set') {
                loadConfig();
                if (config.services[json.service]) {
                    config.services[json.service].port = json.port;
                    saveConfig(config);
                    return sendJson({ success: true, message: "Port updated" });
                }
                return sendJson({ success: false });
            }
            if (pathname === '/api/phpinfo') return sendJson(runPsModule('$meta = Get-ServiceMeta -RootDir $Root; $php = Join-Path $Root "bin\\php\\$($meta.php.active)\\php.exe"; & $php -i'));

            return sendJson(runPsModule(`Write-Output '{"success":false,"message":"Route fallback: ${pathname}"}'`));
        }

        // --- STATIC FILES ---
        const dashDir = path.join(rootDir, 'devstack-dashboard');
        let filePath = path.join(dashDir, pathname === '/' ? 'index.html' : pathname);
        
        if (filePath.endsWith('favicon.ico')) { res.writeHead(204); res.end(); return; }

        fs.readFile(filePath, (err, content) => {
            if (err) {
                res.writeHead(404);
                res.end('Not found');
            } else {
                const ext = path.extname(filePath);
                res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
                res.end(content);
            }
        });
    });
});

server.listen(apiPort, 'localhost', () => {
    writeLog('system', `TDZ DevStack API started on port ${apiPort} (Node.js)`);
});
