# Role: lemp_stack (Step 2)

Installs and secures the LEMP stack: nginx, MariaDB, PHP-FPM.

## What it does

- Installs nginx, mariadb-server, and PHP-FPM + extensions (`php_extensions`)
- Secures MariaDB (equivalent of `mysql_secure_installation`): removes anonymous users and the test DB; root stays on unix_socket auth (secure Ubuntu default)
- Creates the WordPress database (utf8mb4) and a dedicated DB user restricted to `localhost` with privileges on that DB only
- Applies PHP overrides (memory, upload size, `expose_php = Off`)

## Key variables

| Variable | Purpose |
|---|---|
| `php_version`, `php_extensions` | PHP runtime |
| `php_memory_limit`, `php_upload_max_filesize`, `php_post_max_size` | PHP limits |
| `wp_db_name`, `wp_db_user`, `wp_db_password` | WordPress database (password from vault) |

Run alone: `ansible-playbook site.yml --tags lemp`
