-- Jumex Fragua — V3 Offline
-- Ejecutar UNA VEZ en Supabase > SQL Editor.
-- Añade soporte idempotente para visitas iniciadas/cerradas sin conexión.
-- No elimina datos ni reemplaza las políticas RLS existentes.

begin;

alter table public.visitas add column if not exists client_visit_id uuid;
alter table public.visitas add column if not exists modo_registro text;
alter table public.visitas add column if not exists hora_inicio_dispositivo timestamptz;
alter table public.visitas add column if not exists hora_fin_dispositivo timestamptz;
alter table public.visitas add column if not exists sincronizado_at timestamptz;

create unique index if not exists uq_visitas_client_visit_id
  on public.visitas(client_visit_id)
  where client_visit_id is not null;

create index if not exists idx_visitas_promotor_fecha
  on public.visitas(codigo_promotor, hora_inicio desc);

-- ============================================================
-- INICIAR VISITA V3
-- Online: registra la entrada inmediatamente con hora del servidor,
-- pero conserva también la hora capturada por el dispositivo.
-- ============================================================
create or replace function public.iniciar_visita_v3(
  p_client_visit_id uuid,
  p_id_tienda text,
  p_lat double precision,
  p_lng double precision,
  p_precision_m double precision,
  p_hora_inicio_dispositivo timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prom public.promotor%rowtype;
  v_tienda public.tiendas%rowtype;
  v_existente public.visitas%rowtype;
  v_dist double precision;
  v_tolerancia double precision;
  v_id bigint;
  v_hora timestamptz;
begin
  if (select auth.uid()) is null then raise exception 'No autenticado'; end if;
  if p_client_visit_id is null then raise exception 'Identificador de visita requerido'; end if;

  select * into v_prom
  from public.promotor
  where auth_user_id = (select auth.uid()) and activo = true
  limit 1;
  if v_prom.id is null then raise exception 'Promotor no autorizado'; end if;

  -- Idempotencia: si esta misma visita ya se creó, devolverla.
  select * into v_existente
  from public.visitas
  where client_visit_id = p_client_visit_id
  limit 1;
  if v_existente.id is not null then
    if v_existente.codigo_promotor <> v_prom.numero_empleado then
      raise exception 'Identificador de visita no autorizado';
    end if;
    return jsonb_build_object(
      'id', v_existente.id,
      'client_visit_id', v_existente.client_visit_id,
      'id_tienda', v_existente.id_tienda,
      'nombre_tienda', v_existente.nombre_tienda,
      'hora_inicio', v_existente.hora_inicio,
      'distancia_entrada_m', v_existente.distancia_entrada_m,
      'estado', v_existente.estado
    );
  end if;

  if p_lat is null or p_lng is null or p_precision_m is null then raise exception 'Ubicación incompleta'; end if;
  if p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then raise exception 'Coordenadas inválidas'; end if;
  if p_precision_m < 0 or p_precision_m > 120 then raise exception 'Precisión GPS insuficiente'; end if;
  if p_hora_inicio_dispositivo is null then raise exception 'Hora de entrada requerida'; end if;
  if p_hora_inicio_dispositivo > now() + interval '15 minutes' then raise exception 'Hora de dispositivo inválida'; end if;
  if p_hora_inicio_dispositivo < now() - interval '30 days' then raise exception 'La visita es demasiado antigua para sincronizar'; end if;

  select * into v_tienda
  from public.tiendas t
  where t.id_tienda::text = p_id_tienda
    and t.activa = true
    and (
      (lower(coalesce(v_prom.rol,'promotor')) = 'supervisor'
       and lower(coalesce(t.zona,'')) = lower(coalesce(v_prom.zona,'')))
      or
      (lower(coalesce(v_prom.rol,'promotor')) <> 'supervisor'
       and lower(coalesce(t.ruta,'')) = lower(coalesce(v_prom.ruta,'')))
    )
  limit 1;
  if v_tienda.id is null then raise exception 'Tienda no autorizada para este promotor'; end if;
  if v_tienda.lat is null or v_tienda.lng is null then raise exception 'La tienda no tiene coordenadas válidas'; end if;

  if exists (
    select 1 from public.visitas v
    where v.codigo_promotor = v_prom.numero_empleado
      and v.hora_fin is null
  ) then raise exception 'Ya existe una visita abierta'; end if;

  v_dist := 6371000.0 * 2.0 * asin(
    sqrt(
      power(sin(radians(p_lat - v_tienda.lat::double precision) / 2.0), 2)
      + cos(radians(v_tienda.lat::double precision))
        * cos(radians(p_lat))
        * power(sin(radians(p_lng - v_tienda.lng::double precision) / 2.0), 2)
    )
  );
  v_tolerancia := 150.0 + least(p_precision_m,120.0);
  if v_dist > v_tolerancia then
    raise exception 'Fuera del radio permitido. Distancia aproximada: % m', round(v_dist);
  end if;

  v_hora := now();
  insert into public.visitas(
    client_visit_id,codigo_promotor,nombre_promotor,id_tienda,nombre_tienda,
    hora_inicio,hora_inicio_dispositivo,ruta,region,
    lat_entrada,lng_entrada,precision_entrada_m,distancia_entrada_m,
    modo_registro,estado,sincronizado_at
  ) values (
    p_client_visit_id,v_prom.numero_empleado,v_prom.nombre_completo,
    v_tienda.id_tienda::text,coalesce(v_tienda.nombre_tienda,v_tienda.cadena),
    v_hora,p_hora_inicio_dispositivo,coalesce(v_prom.ruta,v_tienda.ruta,''),
    coalesce(v_prom.region,v_prom.zona,''),p_lat,p_lng,p_precision_m,v_dist,
    'ONLINE','EN_VISITA',now()
  ) returning id into v_id;

  return jsonb_build_object(
    'id',v_id,'client_visit_id',p_client_visit_id,
    'id_tienda',v_tienda.id_tienda::text,
    'nombre_tienda',coalesce(v_tienda.nombre_tienda,v_tienda.cadena),
    'hora_inicio',v_hora,'hora_inicio_dispositivo',p_hora_inicio_dispositivo,
    'distancia_entrada_m',v_dist,'estado','EN_VISITA'
  );
end;
$$;

revoke all on function public.iniciar_visita_v3(uuid,text,double precision,double precision,double precision,timestamptz) from public, anon;
grant execute on function public.iniciar_visita_v3(uuid,text,double precision,double precision,double precision,timestamptz) to authenticated;

-- ============================================================
-- SINCRONIZAR / FINALIZAR VISITA V3
-- Sirve tanto para una visita iniciada online como para una visita
-- completamente offline. Es idempotente por client_visit_id.
-- ============================================================
create or replace function public.sincronizar_visita_v3(
  p_client_visit_id uuid,
  p_id_tienda text,
  p_hora_inicio_dispositivo timestamptz,
  p_lat double precision,
  p_lng double precision,
  p_precision_m double precision,
  p_hora_fin_dispositivo timestamptz,
  p_respuestas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prom public.promotor%rowtype;
  v_tienda public.tiendas%rowtype;
  v_visita public.visitas%rowtype;
  v_dist double precision;
  v_tolerancia double precision;
  v_inicio timestamptz;
  v_fin timestamptz;
  v_duracion integer;
  v_id bigint;
  v_required text[] := array[
    'inventario_hydrolit_manzana','inventario_hydrolit_uva','inventario_hydrolit_coco',
    'inventario_hydrolit_naranja_mandarina','inventario_hydrolit_fresa',
    'hydrolit_anaquel','hydrolit_frentes_anaquel','hydrolit_cabecera',
    'hydrolit_refrigerador','hydrolit_frentes_refrigerador',
    'inventario_xot','xot_frentes_refrigerador','xot_candado',
    'xot_exhibicion_adicional','xot_cantidad_exhibiciones',
    'hydrolit_exhibicion_adicional','hydrolit_cantidad_exhibiciones',
    'inventario_blist_uva','inventario_blist_limonada_rosa','blist_anaquel',
    'blist_frentes_anaquel','blist_refrigerador','blist_frentes_refrigerador',
    'blist_exhibicion_adicional','blist_cantidad_exhibiciones'
  ];
begin
  if (select auth.uid()) is null then raise exception 'No autenticado'; end if;
  if p_client_visit_id is null then raise exception 'Identificador de visita requerido'; end if;
  if p_respuestas is null or jsonb_typeof(p_respuestas) <> 'object' then raise exception 'Respuestas inválidas'; end if;
  if not (p_respuestas ?& v_required) then raise exception 'Faltan respuestas obligatorias'; end if;

  select * into v_prom
  from public.promotor
  where auth_user_id = (select auth.uid()) and activo = true
  limit 1;
  if v_prom.id is null then raise exception 'Promotor no autorizado'; end if;

  if p_lat is null or p_lng is null or p_precision_m is null then raise exception 'Ubicación incompleta'; end if;
  if p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then raise exception 'Coordenadas inválidas'; end if;
  if p_precision_m < 0 or p_precision_m > 120 then raise exception 'Precisión GPS insuficiente'; end if;
  if p_hora_inicio_dispositivo is null or p_hora_fin_dispositivo is null then raise exception 'Horas de visita incompletas'; end if;
  if p_hora_fin_dispositivo < p_hora_inicio_dispositivo then raise exception 'La hora de salida es anterior a la entrada'; end if;
  if p_hora_fin_dispositivo > now() + interval '15 minutes' then raise exception 'Hora de dispositivo inválida'; end if;
  if p_hora_inicio_dispositivo < now() - interval '30 days' then raise exception 'La visita es demasiado antigua para sincronizar'; end if;
  if p_hora_fin_dispositivo - p_hora_inicio_dispositivo > interval '12 hours' then raise exception 'Duración de visita fuera de rango'; end if;

  select * into v_tienda
  from public.tiendas t
  where t.id_tienda::text = p_id_tienda
    and t.activa = true
    and (
      (lower(coalesce(v_prom.rol,'promotor')) = 'supervisor'
       and lower(coalesce(t.zona,'')) = lower(coalesce(v_prom.zona,'')))
      or
      (lower(coalesce(v_prom.rol,'promotor')) <> 'supervisor'
       and lower(coalesce(t.ruta,'')) = lower(coalesce(v_prom.ruta,'')))
    )
  limit 1;
  if v_tienda.id is null then raise exception 'Tienda no autorizada para este promotor'; end if;
  if v_tienda.lat is null or v_tienda.lng is null then raise exception 'La tienda no tiene coordenadas válidas'; end if;

  v_dist := 6371000.0 * 2.0 * asin(
    sqrt(
      power(sin(radians(p_lat - v_tienda.lat::double precision) / 2.0), 2)
      + cos(radians(v_tienda.lat::double precision))
        * cos(radians(p_lat))
        * power(sin(radians(p_lng - v_tienda.lng::double precision) / 2.0), 2)
    )
  );
  v_tolerancia := 150.0 + least(p_precision_m,120.0);
  if v_dist > v_tolerancia then
    raise exception 'Fuera del radio permitido. Distancia aproximada: % m', round(v_dist);
  end if;

  select * into v_visita
  from public.visitas
  where client_visit_id = p_client_visit_id
  limit 1
  for update;

  -- Si ya quedó completa, devolver éxito sin duplicar nada.
  if v_visita.id is not null and v_visita.hora_fin is not null then
    if v_visita.codigo_promotor <> v_prom.numero_empleado then raise exception 'Visita no autorizada'; end if;
    return jsonb_build_object(
      'visita_id',v_visita.id,'client_visit_id',p_client_visit_id,
      'hora_salida',v_visita.hora_fin,'duracion_min',v_visita.duracion_min,
      'estado','COMPLETADA','ya_sincronizada',true
    );
  end if;

  if v_visita.id is not null then
    if v_visita.codigo_promotor <> v_prom.numero_empleado then raise exception 'Visita no autorizada'; end if;
    if v_visita.id_tienda::text <> v_tienda.id_tienda::text then raise exception 'La tienda no coincide con la visita iniciada'; end if;
    v_id := v_visita.id;
    v_inicio := v_visita.hora_inicio;
    v_fin := p_hora_fin_dispositivo;
  else
    -- Visita completamente offline: usar horas capturadas por el dispositivo.
    v_inicio := p_hora_inicio_dispositivo;
    v_fin := p_hora_fin_dispositivo;
    insert into public.visitas(
      client_visit_id,codigo_promotor,nombre_promotor,id_tienda,nombre_tienda,
      hora_inicio,hora_fin,hora_inicio_dispositivo,hora_fin_dispositivo,
      ruta,region,lat_entrada,lng_entrada,precision_entrada_m,distancia_entrada_m,
      modo_registro,estado,sincronizado_at
    ) values (
      p_client_visit_id,v_prom.numero_empleado,v_prom.nombre_completo,
      v_tienda.id_tienda::text,coalesce(v_tienda.nombre_tienda,v_tienda.cadena),
      v_inicio,v_fin,p_hora_inicio_dispositivo,p_hora_fin_dispositivo,
      coalesce(v_prom.ruta,v_tienda.ruta,''),coalesce(v_prom.region,v_prom.zona,''),
      p_lat,p_lng,p_precision_m,v_dist,'OFFLINE','COMPLETADA',now()
    ) returning id into v_id;
  end if;

  -- Insertar levantamiento una sola vez. Los CHECK constraints existentes
  -- siguen validando coherencia de inventario/frentes/exhibiciones.
  if not exists (select 1 from public.levantamientos where visita_id = v_id) then
    insert into public.levantamientos(
      visita_id,codigo_promotor,nombre_promotor,region,ruta,id_tienda,nombre_tienda,marca_temporal,
      inventario_hydrolit_manzana,inventario_hydrolit_uva,inventario_hydrolit_coco,
      inventario_hydrolit_naranja_mandarina,inventario_hydrolit_fresa,
      hydrolit_anaquel,hydrolit_frentes_anaquel,hydrolit_cabecera,
      hydrolit_refrigerador,hydrolit_frentes_refrigerador,
      inventario_xot,xot_frentes_refrigerador,xot_candado,xot_exhibicion_adicional,xot_cantidad_exhibiciones,
      hydrolit_exhibicion_adicional,hydrolit_cantidad_exhibiciones,
      inventario_blist_uva,inventario_blist_limonada_rosa,blist_anaquel,blist_frentes_anaquel,
      blist_refrigerador,blist_frentes_refrigerador,blist_exhibicion_adicional,blist_cantidad_exhibiciones,
      motivo_todo_cero,confirmado_todo_cero
    ) values (
      v_id,v_prom.numero_empleado,v_prom.nombre_completo,
      coalesce(v_prom.region,v_prom.zona,''),coalesce(v_prom.ruta,v_tienda.ruta,''),
      v_tienda.id_tienda::text,coalesce(v_tienda.nombre_tienda,v_tienda.cadena),p_hora_fin_dispositivo,
      (p_respuestas->>'inventario_hydrolit_manzana')::integer,
      (p_respuestas->>'inventario_hydrolit_uva')::integer,
      (p_respuestas->>'inventario_hydrolit_coco')::integer,
      (p_respuestas->>'inventario_hydrolit_naranja_mandarina')::integer,
      (p_respuestas->>'inventario_hydrolit_fresa')::integer,
      (p_respuestas->>'hydrolit_anaquel')::boolean,
      (p_respuestas->>'hydrolit_frentes_anaquel')::integer,
      (p_respuestas->>'hydrolit_cabecera')::boolean,
      (p_respuestas->>'hydrolit_refrigerador')::boolean,
      (p_respuestas->>'hydrolit_frentes_refrigerador')::integer,
      (p_respuestas->>'inventario_xot')::integer,
      (p_respuestas->>'xot_frentes_refrigerador')::integer,
      (p_respuestas->>'xot_candado')::boolean,
      (p_respuestas->>'xot_exhibicion_adicional')::boolean,
      (p_respuestas->>'xot_cantidad_exhibiciones')::integer,
      (p_respuestas->>'hydrolit_exhibicion_adicional')::boolean,
      (p_respuestas->>'hydrolit_cantidad_exhibiciones')::integer,
      (p_respuestas->>'inventario_blist_uva')::integer,
      (p_respuestas->>'inventario_blist_limonada_rosa')::integer,
      (p_respuestas->>'blist_anaquel')::boolean,
      (p_respuestas->>'blist_frentes_anaquel')::integer,
      (p_respuestas->>'blist_refrigerador')::boolean,
      (p_respuestas->>'blist_frentes_refrigerador')::integer,
      (p_respuestas->>'blist_exhibicion_adicional')::boolean,
      (p_respuestas->>'blist_cantidad_exhibiciones')::integer,
      nullif(trim(coalesce(p_respuestas->>'motivo_todo_cero','')),''),
      coalesce((p_respuestas->>'confirmado_todo_cero')::boolean,false)
    );
  end if;

  v_duracion := greatest(0,round(extract(epoch from (v_fin - v_inicio))/60.0)::integer);

  update public.visitas
  set hora_fin = v_fin,
      hora_fin_dispositivo = p_hora_fin_dispositivo,
      duracion_min = v_duracion,
      cumple_tiempo = (v_duracion >= 40),
      estado = 'COMPLETADA',
      distancia_entrada_m = v_dist,
      sincronizado_at = now()
  where id = v_id;

  return jsonb_build_object(
    'visita_id',v_id,'client_visit_id',p_client_visit_id,
    'hora_salida',v_fin,'duracion_min',v_duracion,'estado','COMPLETADA',
    'ya_sincronizada',false
  );
end;
$$;

revoke all on function public.sincronizar_visita_v3(uuid,text,timestamptz,double precision,double precision,double precision,timestamptz,jsonb) from public, anon;
grant execute on function public.sincronizar_visita_v3(uuid,text,timestamptz,double precision,double precision,double precision,timestamptz,jsonb) to authenticated;

commit;
