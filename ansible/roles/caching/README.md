# Role: caching (Step 5)

Three cache layers for efficiency, plus compression.

## What it does

- **OPcache** — precompiled PHP bytecode (biggest single win)
- **Redis object cache** — installs Redis (memory-capped, `allkeys-lru`), the Redis Object Cache plugin, and enables the `object-cache.php` drop-in via WP-CLI
- **FastCGI page cache** — creates the cache directory; the zone and vhost directives are rendered by the `wordpress` role's vhost template, toggled by `enable_fastcgi_cache`. Cached pages are served without touching PHP; logged-in users, POSTs, admin, and feeds bypass the cache. Check the `X-FastCGI-Cache` response header (`HIT`/`MISS`/`BYPASS`)
- **gzip** — compresses text assets; static files also get long `expires` headers via the vhost

## Key variables

| Variable | Purpose |
|---|---|
| `opcache_memory` | OPcache size (MB) |
| `enable_redis_cache`, `redis_maxmemory` | Object cache |
| `enable_fastcgi_cache`, `fastcgi_cache_path/size/valid` | Page cache |
| `static_expires` | Browser cache lifetime for static assets |

## Notes

- Redis plugin activation requires an installed site; if `wp_auto_install` was false and you finished setup in the browser, re-run: `ansible-playbook site.yml --tags caching`
- For a CDN layer, put CloudFront in front — no changes needed here.

Run alone: `ansible-playbook site.yml --tags caching`
