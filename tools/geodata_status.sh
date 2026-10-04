#!/usr/bin/env bash
# Visar vad som finns i geodatabasen och hur mycket plats det tar (gratisnivån: 500 MB).
source "$(dirname "$0")/geodata.sh"
psql "$HITOCHDIT_DB" -q -c "
  select kalla, typ, count(*) as antal, max(uppdaterad)::date as uppdaterad,
         pg_size_pretty(sum(pg_column_size(geom))::bigint) as geometri
  from public.objekt group by kalla, typ order by kalla;" \
  -c "select pg_size_pretty(pg_total_relation_size('public.objekt')) as objekt_inkl_index,
             pg_size_pretty(pg_database_size(current_database())) as hela_databasen;"
