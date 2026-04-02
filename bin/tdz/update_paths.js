const fs = require('fs');
const path = require('path');

const rootDir = process.cwd();
const rootUnix = rootDir.replace(/\\/g, '/');
const rootFile = path.join(rootDir, 'usr', '.tdz-root');

let oldRootUnix = '';
if (fs.existsSync(rootFile)) {
    oldRootUnix = fs.readFileSync(rootFile, 'utf8').trim();
} else {
    // Dynamically detect old root by reading httpd.conf
    try {
        const apacheDirs = fs.readdirSync(path.join(rootDir, 'bin', 'apache'));
        const activeApache = apacheDirs.find(d => fs.existsSync(path.join(rootDir, 'bin', 'apache', d, 'conf', 'httpd.conf')));
        if (activeApache) {
            const httpdConf = fs.readFileSync(path.join(rootDir, 'bin', 'apache', activeApache, 'conf', 'httpd.conf'), 'utf8');
            const match = httpdConf.match(/Define SRVROOT "([^"]+)\/bin\/apache/i);
            if (match && match[1]) {
                oldRootUnix = match[1];
            }
        }
    } catch(e) {}
    
    // If still not found, return silently
    if (!oldRootUnix) {
        fs.writeFileSync(rootFile, rootUnix, 'utf8');
        process.exit(0);
    }
}

// If unchanged, exit fast
if (oldRootUnix.toLowerCase() === rootUnix.toLowerCase()) {
    process.exit(0);
}

console.log(`[Auto-Repair] TDZ DevStack moved!`);
console.log(`[Auto-Repair] Old path: ${oldRootUnix}`);
console.log(`[Auto-Repair] New path: ${rootUnix}`);
console.log(`[Auto-Repair] Updating config files...`);

// Files to search and replace
const searchPatterns = [
    'bin/apache/*/conf/httpd.conf',
    'bin/php/*/php.ini',
    'etc/apache2/*.conf',
    'etc/apache2/sites-enabled/*.conf',
    'etc/apache2/alias/*.conf'
];

// Simple glob implementation
function getFiles(pattern) {
    const parts = pattern.split('/');
    let currentDirs = [rootDir];
    
    for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        const nextDirs = [];
        
        for (const dir of currentDirs) {
            if (!fs.existsSync(dir)) continue;
            
            if (part === '**') {
                // not implemented, not needed here
            } else if (part.includes('*')) {
                const regex = new RegExp('^' + part.replace(/\*/g, '.*') + '$');
                const items = fs.readdirSync(dir);
                for (const item of items) {
                    if (regex.test(item)) {
                        nextDirs.push(path.join(dir, item));
                    }
                }
            } else {
                const fullPath = path.join(dir, part);
                if (i === parts.length - 1) {
                    if (fs.existsSync(fullPath)) nextDirs.push(fullPath);
                } else {
                    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory()) {
                        nextDirs.push(fullPath);
                    }
                }
            }
        }
        currentDirs = nextDirs;
    }
    return currentDirs;
}

let updatedKeys = 0;
searchPatterns.forEach(pattern => {
    const files = getFiles(pattern);
    files.forEach(file => {
        if (!fs.statSync(file).isFile()) return;
        
        let content = fs.readFileSync(file, 'utf8');
        // Case insensitive replacement
        const regex = new RegExp(oldRootUnix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
        
        if (regex.test(content)) {
            content = content.replace(regex, rootUnix);
            fs.writeFileSync(file, content, 'utf8');
            updatedKeys++;
            console.log(`  -> Updated: ${file.replace(rootDir, '').substring(1)}`);
        }
    });
});

console.log(`[Auto-Repair] Updated ${updatedKeys} files.`);
fs.writeFileSync(rootFile, rootUnix, 'utf8');
process.exit(0);
