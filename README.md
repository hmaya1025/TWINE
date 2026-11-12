# TWINE

Base de despliegue de `twineprotein.com` en el VPS `177.7.57.250`.

## Estructura

- `site/`: contenido estático servido por Nginx dentro de Docker.
- `Dockerfile`: imagen de producción.
- `deploy/compose.production.yml`: contenedor aislado en `127.0.0.1:8081`.
- `deploy/`: publicación por SSH, activación con reversión y virtual host TLS propio.
- `.github/workflows/production-deploy.yml`: validación para PR y despliegue al integrar en `main`.

La página incluida es solo una pantalla temporal de configuración. El sitio final se puede sustituir en `site/` sin cambiar el flujo de despliegue.

## GitHub Actions

El workflow usa el entorno de GitHub `production`. Configura estas **variables de entorno**:

| Nombre | Valor |
| --- | --- |
| `DEPLOY_HOST` | `177.7.57.250` |
| `DEPLOY_USER` | `root` |
| `DEPLOY_PORT` | `22` |

Configura estos **secretos de entorno**:

| Nombre | Contenido |
| --- | --- |
| `PRODUCTION_SSH_PRIVATE_KEY` | Contenido completo de `%USERPROFILE%\.ssh\twine_actions` |
| `PRODUCTION_KNOWN_HOSTS` | Líneas verificadas para `177.7.57.250` de `%USERPROFILE%\.ssh\known_hosts` |

El workflow valida y construye Docker en PR contra `main`. Los cambios integrados a `main` se despliegan a `/opt/twineprotein`; el contenedor usa el proyecto `twine-production` y el puerto local `8081`. El virtual host y el certificado se gestionan con nombres exclusivos de Twine.

## DNS y primer despliegue

Los registros A de `twineprotein.com` y `www.twineprotein.com` deben resolver únicamente a `177.7.57.250`. El servidor instala su propio sitio Nginx en `/etc/nginx/sites-available/twineprotein.com` y emite un certificado Let's Encrypt para ambos nombres. El script aborta antes de modificar Nginx si los DNS no apuntan al VPS o si ya hay una configuración de Twine no administrada por este proyecto.

Para desplegar manualmente desde PowerShell con la clave Twine cargada en `ssh-agent`:

```powershell
.\deploy\deploy.ps1 -SshTarget root@177.7.57.250 -SshPort 22
```

Los despliegues mantienen releases bajo `/opt/twineprotein/releases`, conservan `current` y `previous`, esperan el health check y restauran la imagen anterior si la nueva no queda saludable.
