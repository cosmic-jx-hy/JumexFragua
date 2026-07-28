-- ============================================================
-- SETUP DE SEGURIDAD — Jumex Fragua
-- Correr esto en Supabase → SQL Editor → New query → Run
-- ============================================================

-- ------------------------------------------------------------
-- 1. Habilitar extensión para hashear PINs
-- ------------------------------------------------------------
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 2. Agregar columna de PIN (hasheado) a la tabla promotor
-- ------------------------------------------------------------
alter table promotor add column if not exists pin_hash text;

-- Asignar un PIN inicial a cada promotor que todavía no tenga uno.
-- Aquí se usa el propio número de empleado como PIN temporal —
-- AJUSTA esta lógica si prefieres asignar PINs distintos manualmente,
-- y comunícale a cada promotor su PIN por un canal separado (no por WhatsApp grupal).
update promotor
set pin_hash = crypt(numero_empleado, gen_salt('bf'))
where pin_hash is null;

-- ------------------------------------------------------------
-- 3. Función que verifica el login del promotor EN EL SERVIDOR.
--    El PIN nunca se compara en el navegador del promotor.
-- ------------------------------------------------------------
create or replace function verificar_promotor(p_codigo text, p_pin text)
returns table (
  numero_empleado text,
  nombre_completo text,
  rol text,
  region text,
  zona text,
  ruta text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select p.numero_empleado, p.nombre_completo, p.rol, p.region, p.zona, p.ruta
  from promotor p
  where p.numero_empleado = p_codigo
    and p.activo = true
    and p.pin_hash is not null
    and p.pin_hash = crypt(p_pin, p.pin_hash);
end;
$$;

-- Permitir que el rol público (anon, sin loguearse en Supabase Auth) ejecute esta función
grant execute on function verificar_promotor(text, text) to anon;

-- ------------------------------------------------------------
-- 4. Cerrar el acceso directo de lectura a la tabla promotor.
--    Antes cualquiera con la anon key podía leer TODA la tabla
--    (nombres, rutas, zonas) directo desde la API REST de Supabase.
--    Ahora solo se puede "entrar" a través de verificar_promotor().
-- ------------------------------------------------------------
alter table promotor enable row level security;

-- Revisa en Authentication → Policies si existe alguna policy de SELECT
-- abierta sobre "promotor" para el rol anon, y bórrala manualmente si aparece.
-- Al no crear ninguna policy de SELECT para anon aquí, la tabla queda
-- cerrada a lectura directa por default.

-- El admin panel SÍ necesita leer la tabla completa de promotores
-- (para mostrar la lista) — eso lo permitimos solo para admins logueados:
drop policy if exists "admin_read_promotor" on promotor;
create policy "admin_read_promotor" on promotor
  for select using (auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- 5. Permitir lectura de checkins / gps_logs / visitas SOLO a usuarios
--    autenticados (es decir, el admin logueado con Supabase Auth).
--    Los promotores siguen pudiendo INSERTAR sin loguearse con Supabase Auth
--    (usan su propio login con PIN, no Supabase Auth).
-- ------------------------------------------------------------
alter table checkins enable row level security;
alter table gps_logs enable row level security;
alter table visitas enable row level security;

drop policy if exists "admin_read_checkins" on checkins;
create policy "admin_read_checkins" on checkins
  for select using (auth.role() = 'authenticated');

drop policy if exists "admin_read_gps_logs" on gps_logs;
create policy "admin_read_gps_logs" on gps_logs
  for select using (auth.role() = 'authenticated');

drop policy if exists "admin_read_visitas" on visitas;
create policy "admin_read_visitas" on visitas
  for select using (auth.role() = 'authenticated');

drop policy if exists "anon_insert_checkins" on checkins;
create policy "anon_insert_checkins" on checkins
  for insert with check (true);

drop policy if exists "anon_insert_gps_logs" on gps_logs;
create policy "anon_insert_gps_logs" on gps_logs
  for insert with check (true);

drop policy if exists "anon_insert_visitas" on visitas;
create policy "anon_insert_visitas" on visitas
  for insert with check (true);

-- ------------------------------------------------------------
-- 6. El admin también necesita crear/editar/desactivar promotores y tiendas,
--    y editar la palabra clave. Todo esto solo para admins autenticados.
-- ------------------------------------------------------------
drop policy if exists "admin_write_promotor" on promotor;
create policy "admin_write_promotor" on promotor
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
-- (esta policy "for all" cubre insert/update/delete; la de select ya se creó arriba)

alter table tiendas enable row level security;

drop policy if exists "anon_read_tiendas" on tiendas;
create policy "anon_read_tiendas" on tiendas
  for select using (true);
-- Las tiendas (nombre, lat, lng) no son información sensible y el promotor
-- las necesita para validar su ruta sin loguearse como admin.

drop policy if exists "admin_write_tiendas" on tiendas;
create policy "admin_write_tiendas" on tiendas
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

alter table palabra_clave enable row level security;

drop policy if exists "anon_read_palabra_clave" on palabra_clave;
create policy "anon_read_palabra_clave" on palabra_clave
  for select using (true);
-- La palabra clave del día ya se comparte con todos los promotores por diseño.

drop policy if exists "admin_write_palabra_clave" on palabra_clave;
create policy "admin_write_palabra_clave" on palabra_clave
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- NOTA IMPORTANTE — pendiente para la siguiente fase:
-- Los INSERT arriba siguen siendo "with check (true)", es decir,
-- cualquiera con la anon key todavía puede insertar checkins/gps falsos
-- directo a la API sin pasar por la validación de distancia de tu app.
-- Esto es lo siguiente que hay que blindar (mover la validación de
-- ruta/distancia a una función server-side), pero no rompe nada de lo
-- que arreglamos hoy — es un paso aparte.
-- ------------------------------------------------------------
