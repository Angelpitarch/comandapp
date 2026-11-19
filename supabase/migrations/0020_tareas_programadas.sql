-- 0020: tareas programadas de la tasa BCV (pg_cron). Seguro de repetir: cron.schedule con el mismo
-- nombre reemplaza la tarea existente.
--
-- Las horas de pg_cron son UTC. Venezuela es UTC-4 todo el ano (sin horario de verano).
--   * tasa-bcv-leer      cada hora al minuto 7: llama a la funcion tasa-bcv, que lee bcv.org.ve y guarda la tasa.
--                        (El BCV publica en la tarde la tasa del dia habil siguiente; leer cada hora tambien cubre
--                        los dias en que la pagina tarda o se cae un rato.)
--   * tasa-bcv-aplicar   04:01 UTC = 12:01 a.m. en Caracas: pone en los negocios la tasa del dia que empieza
--                        (la que el BCV publico el dia anterior con esa fecha valor).
--   * limpiar-historial  domingos: borra el registro de ejecuciones de mas de 7 dias.
--
-- El secreto que se envia a la funcion se lee de private.app_secrets en cada ejecucion: no esta escrito aqui.

create extension if not exists pg_cron;

select cron.schedule('tasa-bcv-leer', '7 * * * *', $job$
  select net.http_post(
    url := 'https://tmjejukvdcfifajnmlca.supabase.co/functions/v1/tasa-bcv',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select value from private.app_secrets where name = 'webhook_notify')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
$job$);

select cron.schedule('tasa-bcv-aplicar', '1 4 * * *', $job$ select private.aplicar_tasa_bcv(null); $job$);

select cron.schedule('limpiar-historial-tareas', '30 5 * * 0', $job$
  delete from cron.job_run_details where end_time < now() - interval '7 days';
$job$);
