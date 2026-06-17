# Instrucciones — Jumex Fragua (versión Supabase)

## Archivos del sistema

| Archivo | Para quién |
|---|---|
| `promotor.html` | Los 22 promotores (en su celular) |
| `admin.html` | Tú (panel de administración) |
| `politicas_rls.sql` | Seguridad de las tablas (se corre una sola vez) |

---

## Paso 1 — Activar las políticas de seguridad

1. Entra a [supabase.com](https://supabase.com) → tu proyecto **JX_HYDROLIT**
2. Ve a **SQL Editor** → **New query**
3. Abre `politicas_rls.sql`, copia todo el contenido y pégalo
4. Clic en **Run**

Esto activa RLS en las 4 tablas y deja exactamente estos permisos:

| Tabla | Leer | Insertar | Editar/Borrar |
|---|---|---|---|
| `promotor` | ✅ | ❌ (se hace desde admin.html con tu login) | ❌ |
| `tiendas` | ✅ | ❌ (se hace desde admin.html al importar Excel) | ❌ |
| `checkins` | ✅ | ✅ | ❌ |
| `gps_logs` | ✅ | ✅ | ❌ |

También activa **Realtime** en `checkins` y `gps_logs`, así el mapa del admin se actualiza solo, sin que tengas que refrescar la página.

---

## Paso 2 — Subir los archivos HTML

Ya tienen tu URL y anon key de Supabase integradas, no necesitas configurar nada más en el código.

**Opción más sencilla — GitHub Pages (gratis):**
1. Crea una cuenta en [github.com](https://github.com) si no tienes
2. Crea un repositorio nuevo (puede ser público, las keys son seguras para frontend)
3. Sube `promotor.html` y `admin.html`
4. Ve a Settings → Pages → Source: main branch
5. Obtienes URLs como:
   - `https://tuusuario.github.io/jumex/promotor.html`
   - `https://tuusuario.github.io/jumex/admin.html`

---

## Paso 3 — Dar de alta a los 22 promotores

1. Abre `admin.html` en tu navegador
2. Ingresa con: usuario `admin`, contraseña `jumex2026`
3. Ve a la pestaña **Promotores**
4. Clic en **+ Nuevo promotor** y registra a cada uno con su número de empleado

---

## Paso 4 — Importar el catálogo de tiendas

1. En el panel Admin → pestaña **Tiendas**
2. Clic en **Importar Excel**
3. Selecciona tu archivo de universo de clientes
4. El sistema detecta las columnas automáticamente (ID Frog, Razón Social, Coordenada X/Y, etc.)

---

## Paso 5 — Compartir el link con los promotores

Comparte la URL de `promotor.html` por WhatsApp. Cada promotor:
1. Abre el link en su celular
2. Da permiso de ubicación cuando el navegador lo solicite
3. Ingresa su número de empleado y nombre
4. Toca **Iniciar jornada** una sola vez en la mañana

El sistema hace todo lo demás automáticamente: GPS cada 5 minutos de 8am a 5pm, cola offline si se pierde la conexión, y checkout automático a las 5pm.

---

## Cambiar la contraseña de admin

En `admin.html`, busca esta línea y cambia el valor:
```javascript
const ADMIN_PASS = 'jumex2026';
```

---

## Limpieza quincenal (proceso manual y seguro)

Por diseño, **no hay botón para borrar datos** desde `admin.html`. Esto es intencional: protege la evidencia de que nadie —ni siquiera con la contraseña de admin de la página— puede alterar o eliminar los registros desde la app pública.

El proceso es:

1. En `admin.html` → pestaña **Exportar / Limpiar** → clic en **Exportar todo lo disponible**
2. Verifica que el archivo Excel se descargó correctamente y ábrelo para confirmar que los datos están completos
3. Entra a [supabase.com](https://supabase.com) → tu proyecto → **Table Editor**
4. Abre la tabla `checkins` o `gps_logs`
5. Si quieres, usa el filtro para acotar por fecha (la columna `fecha`)
6. Selecciona las filas con el checkbox de la izquierda (puedes seleccionar todas con el checkbox del encabezado)
7. Clic en **Delete rows** (botón rojo arriba a la derecha)
8. Confirma

Repite para ambas tablas. Los datos de `promotor` y `tiendas` nunca se tocan en este proceso.

---

## Lo que incluye el sistema

**Promotor (celular)**
- Login con número de empleado y nombre
- Check-in único al iniciar jornada, con coordenadas
- GPS automático cada 5 minutos de 8am a 5pm
- Cola offline: si no hay datos móviles, los registros se guardan en el celular y se envían solos al reconectar
- Alerta visual si el GPS pierde señal más de 10 minutos
- Checkout automático a las 5pm
- Sesión persistente: si cierra la pestaña, al volver lo reconoce sin pedir login de nuevo (mismo día)

**Admin (tú)**
- Mapa en tiempo real (Realtime de Supabase, sin necesidad de refrescar)
- Sidebar con los 22 promotores y punto verde si ya hicieron check-in
- Estadísticas del día: check-ins, registros GPS, pendientes
- Alta y baja de promotores
- Importación de catálogo de tiendas desde Excel
- Exportación a Excel con 3 pestañas: check-ins, GPS, promotores
- Guía paso a paso para la limpieza quincenal manual en Supabase

---

## Soporte técnico

Si algo no funciona, verifica en este orden:
1. ¿Corriste el `politicas_rls.sql` completo en Supabase?
2. ¿El promotor le dio permiso de ubicación al navegador?
3. ¿El número de empleado existe en la tabla `promotor` con `activo = true`?
4. Si el mapa no se actualiza solo, revisa que Realtime esté habilitado (paso 1)
