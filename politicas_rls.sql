-- ============================================================
--  JUMEX FRAGUA — Políticas de seguridad RLS
--  Pega TODO este archivo en Supabase → SQL Editor → New query
--  Luego clic en "Run"
-- ============================================================

-- ------------------------------------------------------------
-- TABLA: promotor
-- Lectura: cualquiera puede leer (necesario para el login)
-- Escritura: bloqueada desde el frontend (altas/bajas las haces
--            tú manualmente desde el Table Editor de Supabase,
--            o desde el panel admin usando una función segura)
-- ------------------------------------------------------------
alter table public.promotor enable row level security;

create policy "Lectura publica promotor"
on public.promotor
for select
to anon
using (true);

-- ------------------------------------------------------------
-- TABLA: tiendas
-- Lectura: cualquiera puede leer (necesario para mostrar tiendas)
-- Escritura: bloqueada desde el frontend
-- ------------------------------------------------------------
alter table public.tiendas enable row level security;

create policy "Lectura publica tiendas"
on public.tiendas
for select
to anon
using (true);

-- ------------------------------------------------------------
-- TABLA: checkins
-- Lectura: cualquiera puede leer (para que el admin vea todo)
-- Insert: cualquiera puede insertar (el promotor hace check-in)
-- Update/Delete: bloqueados, nadie puede alterar un check-in
--                una vez creado (esto protege la evidencia)
-- ------------------------------------------------------------
alter table public.checkins enable row level security;

create policy "Lectura publica checkins"
on public.checkins
for select
to anon
using (true);

create policy "Insertar checkins"
on public.checkins
for insert
to anon
with check (true);

-- ------------------------------------------------------------
-- TABLA: gps_logs
-- Lectura: cualquiera puede leer (para el mapa del admin)
-- Insert: cualquiera puede insertar (el promotor manda su GPS)
-- Update/Delete: bloqueados, mismo motivo que checkins
-- ------------------------------------------------------------
alter table public.gps_logs enable row level security;

create policy "Lectura publica gps_logs"
on public.gps_logs
for select
to anon
using (true);

create policy "Insertar gps_logs"
on public.gps_logs
for insert
to anon
with check (true);

-- ============================================================
--  Nota sobre la limpieza quincenal
--  El admin.html usa la anon key para insertar/leer, pero el
--  DELETE para limpiar gps_logs/checkins NO está permitido aquí
--  a propósito. Eso lo harás directamente desde el Table Editor
--  de Supabase, para que nadie pueda borrar evidencia desde la
--  app pública. Ver INSTRUCCIONES.md para el paso a paso.
-- ============================================================

-- ------------------------------------------------------------
--  HABILITAR REALTIME (para que el mapa del admin se actualice
--  solo, sin necesidad de refrescar la página)
-- ------------------------------------------------------------
alter publication supabase_realtime add table public.gps_logs;
alter publication supabase_realtime add table public.checkins;
