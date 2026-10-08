-- Slott och herrgårdar (SH) 2026-10-09. Körd via Claude. Går att köra om.
-- Ny källa i public.objekt, kategori kultur. Data laddas med tools/ladda_slott.sh (supabase/ladda/slott.sql).
-- Märkesgrupp: marke_grupp() ger 'SH' automatiskt (okänd källa = egen grupp). Topplistor: kalla_kategori nedan.
create or replace function public.kalla_kategori(k text) returns text
language sql immutable set search_path = '' as $$
  select case when k in ('NR', 'NP', 'NM') then 'natur'
              when k in ('KR', 'VA', 'BM', 'FL', 'KY', 'KO', 'FY', 'SH') then 'kultur'
              when k in ('TA', 'SJ', 'OE', 'TO') then 'geo' end;
$$;
