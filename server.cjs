const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const host = '127.0.0.1';
const port = Number(process.env.PORT || 8000);
const routes = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/styles.css', ['styles.css', 'text/css; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/experience.js', ['experience.js', 'text/javascript; charset=utf-8']],
]);
// Only flat game modules/styles are public. Configuration, tests and .git stay private.
function systemRoute(pathname) {
  return /^\/systems\/[a-z0-9-]+\.(js|css)$/.test(pathname)
    ? [pathname.slice(1),pathname.endsWith('.css')?'text/css; charset=utf-8':'text/javascript; charset=utf-8'] : null;
}
const assetTypes = new Map([
  ['.fbx', 'application/octet-stream'],
  ['.obj', 'text/plain; charset=utf-8'],
  ['.mtl', 'text/plain; charset=utf-8'],
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.webp', 'image/webp'],
  ['.mp3', 'audio/mpeg'],
]);
const clients = new Set();
const reloadScript = `<script>const previewUpdates = new EventSource('/__updates'); previewUpdates.addEventListener('refresh', () => {
  if (!document.querySelector('#startScreen')?.hidden) { location.reload(); return; }
  if (document.getElementById('previewRefresh')) return;
  const update = document.createElement('button'); update.id = 'previewRefresh'; update.textContent = 'Atualização pronta · reiniciar para aplicar';
  update.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:150;background:#eac47b;color:#202c2e;border:0;border-radius:4px;padding:9px 14px;font:600 11px sans-serif;cursor:pointer';
  update.onclick = () => location.reload(); document.body.append(update);
});</script>`;

const server = http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.writeHead(405, { Allow: 'GET, HEAD' });
    return res.end();
  }
  const pathname = decodeURIComponent(new URL(req.url, `http://${host}:${port}`).pathname);
  if (pathname === '/__updates' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
    res.write(': connected\n\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }
  if (pathname === '/favicon.ico') {
    res.writeHead(204);
    return res.end();
  }
  if (pathname.startsWith('/assets/')) {
    const assetPath = path.resolve(__dirname, `.${pathname}`);
    const assetsRoot = path.resolve(__dirname, 'assets') + path.sep;
    if (!assetPath.startsWith(assetsRoot) || !assetTypes.has(path.extname(assetPath).toLowerCase())) {
      res.writeHead(403);
      return res.end('Forbidden');
    }
    fs.readFile(assetPath, (error, body) => {
      if (error) {
        res.writeHead(404);
        return res.end('Asset not found.');
      }
      res.writeHead(200, { 'Content-Type': assetTypes.get(path.extname(assetPath).toLowerCase()), 'Cache-Control': 'no-store' });
      if (req.method === 'HEAD') return res.end();
      res.end(body);
    });
    return;
  }
  const route = routes.get(pathname) || systemRoute(pathname);
  if (!route) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Not found');
  }
  fs.readFile(path.join(__dirname, route[0]), 'utf8', (error, body) => {
    if (error) {
      res.writeHead(500);
      return res.end('Could not read the page.');
    }
    res.writeHead(200, { 'Content-Type': route[1], 'Cache-Control': 'no-store' });
    if (req.method === 'HEAD') return res.end();
    res.end(route[0] === 'index.html' ? body.replace('</body>', `${reloadScript}</body>`) : body);
  });
});

let refreshTimer;
function refreshPreview(){
  clearTimeout(refreshTimer);
  refreshTimer=setTimeout(()=>{for(const response of clients)response.write('event: refresh\ndata: updated\n\n');},350);
}
const watcher = fs.watch(__dirname, (event, filename) => {
  if (!['index.html', 'styles.css', 'app.js', 'experience.js'].includes(String(filename))) return;
  refreshPreview();
});
const systemWatcher=fs.watch(path.join(__dirname,'systems'),(event,filename)=>{if(/\.(js|css)$/.test(String(filename)))refreshPreview();});
server.on('error', (error) => {
  console.error(`Meyui Beuyi could not start: ${error.message}`);
  watcher.close();
  systemWatcher.close();
  process.exitCode = 1;
});
server.listen(port, host, () => console.log(`Meyui Beuyi running at http://${host}:${port} (auto-refresh enabled)`));
