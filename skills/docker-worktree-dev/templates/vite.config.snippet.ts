// =============================================================================
// vite.config.ts — server block that consumes the Makefile's exported env.
// =============================================================================
// The Makefile computes the dynamic nip.io host, the API proxy target, and the
// HMR polling flag, then exports them. Vite must read them or the exports wire
// to nothing: the browser host is rejected (Vite blocks unknown hosts), the
// /api proxy points nowhere, and HMR is silent over the Docker bind mount.
// Merge this `server` block into your existing defineConfig.
// =============================================================================

import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const apiProxyTarget =
    env.VITE_API_PROXY_TARGET || env.VITE_API_BASE_URL || 'http://localhost:8000';

  return {
    // ...your plugins, resolve, etc.
    server: {
      port: 3000,
      // Accept the worktree's nip.io host (Vite blocks non-allowed hosts).
      allowedHosts: [
        ...(env.VITE_ALLOWED_HOST ? [env.VITE_ALLOWED_HOST] : []),
      ],
      // In-container same-origin calls: browser hits /api, Vite proxies to the
      // api service over the Docker network. `ws: true` carries WebSockets.
      proxy: {
        '/api': {
          target: apiProxyTarget,
          changeOrigin: true,
          ws: true,
          rewrite: (p) => p.replace(/^\/api/, ''),
        },
      },
      // inotify events don't cross host→container bind mounts on Linux, so
      // file edits are invisible to Vite without polling.
      watch: {
        usePolling: env.VITE_USE_POLLING === 'true',
      },
    },
  };
});
