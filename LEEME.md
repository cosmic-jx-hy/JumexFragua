# Cómo aplicar estos cambios

## 1. Corre el SQL en Supabase
1. Entra a tu proyecto en supabase.com → **SQL Editor** → **New query**
2. Pega todo el contenido de `01_setup_seguridad.sql` y dale **Run**
3. Si algo falla porque el nombre de una tabla o columna no coincide exactamente con
   el tuyo (por ejemplo si `checkins` se llama distinto), ajústalo antes de correrlo.

## 2. Crea el usuario admin en Supabase Auth
1. En tu proyecto Supabase → **Authentication** → **Providers** → confirma que
   "Email" esté habilitado.
2. **Authentication** → **Users** → **Add user** → **Create new user**
   - Correo: el que quieras usar para entrar al panel (ej. `admin@jumexfragua.com`)
   - Contraseña: una nueva, fuerte, distinta a "jumex2026"
   - Marca "Auto Confirm User" para no tener que confirmar por correo
3. Ya no hay ningún usuario/password escrito en el código — vive solo en Supabase.

## 3. Asigna PIN a los promotores
El SQL les puso como PIN temporal su propio número de empleado. Esto es solo
para no romper el sistema hoy mismo — **díselo a cada promotor por un canal
directo (no en el grupo de WhatsApp)** y pídeles usar ese PIN, o mejor, define
tú un PIN distinto por promotor y actualiza `pin_hash` manualmente:

```sql
update promotor
set pin_hash = crypt('el_pin_que_quieras', gen_salt('bf'))
where numero_empleado = '1023';
```

## 4. Sube los archivos actualizados
Reemplaza tu `admin.html` e `index.html` actuales por los de esta carpeta.
No cambian nada de tu diseño ni de tu flujo — solo el login.

## Qué quedó resuelto
- ✅ El password del admin ya no está en el código fuente (Supabase Auth)
- ✅ El login de promotor ahora valida un PIN real, con hash, verificado en el servidor
- ✅ La tabla `promotor` ya no se puede leer directo con la anon key expuesta
- ✅ Checkins, GPS logs y visitas solo se pueden leer si estás autenticado como admin

## Qué queda pendiente (siguiente fase)
- La validación de "estás dentro del radio de tu ruta" para el check-in sigue
  corriendo en el navegador del promotor — un usuario técnico todavía podría
  insertar un checkin falso saltándose esa validación. Para cerrar esto del
  todo hay que mover esa lógica a una función de servidor (trigger o Edge
  Function) que rechace el insert si la distancia no cuadra.
- Detección de mock location / GPS spoofing — no está implementada todavía.
