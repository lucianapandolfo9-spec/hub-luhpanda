-- ============================================================
-- HUB LUH PANDA — 019: fone_norm não pode atropelar DDI internacional
--
-- Aplicada em 24/09/2026, sessão de conversas de WhatsApp (Bloco C).
--
-- Achado ao cadastrar o WhatsApp real da GL4/Gigi (Lymphatic by Gigi, LA):
-- número americano "+1 747 275 5982" reduz a 11 dígitos —
-- "17472755982". A regra antiga de hub.fone_norm() prefixava 55 em
-- QUALQUER número de 10 ou 11 dígitos, sem checar se já vinha com um DDI
-- diferente. Isso vira "5517472755982" (13 dígitos) e cai na branch de
-- BR, que tentaria ler "17" como DDD — número interpretado errado, e o
-- envio pela Edge Function (que manda o fone canonicalizado pro Evolution)
-- ia quebrar com "jid: ...@s.whatsapp.net, exists:false" — o MESMO erro
-- que já tinha acontecido com o ID de grupo do "The Best" (não é bug novo,
-- é a mesma causa raiz: heurística de tamanho de dígito não é DDI).
--
-- Fix: nenhum DDD brasileiro começa com 1 (vão de 11 a 99, primeiro
-- dígito 1 nunca aparece) — então um número de 11 dígitos que começa com
-- "1" quase certamente já é DDI+número de outro país (EUA/Canadá: 1 + DDD
-- de 3 + número de 7 = 11), não BR sem DDI. 10 dígitos continua sempre
-- prefixando 55 (fixo BR sem DDI só existe nesse tamanho).
-- ============================================================

create or replace function hub.fone_norm(p_fone text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v text;
  v_ddd int;
  v_resto text;
begin
  if p_fone is null then
    return null;
  end if;

  -- corta o que vier depois de @ (JID de contato ou de grupo)
  v := split_part(p_fone, '@', 1);

  -- reduz a dígitos
  v := regexp_replace(v, '\D', '', 'g');

  if v = '' then
    return null;
  end if;

  -- sem DDI: DDD (2) + número (8 ou 9) = 10 ou 11 dígitos → prefixa 55.
  -- Exceção: 11 dígitos começando com "1" não é BR sem DDI (nenhum DDD
  -- brasileiro começa com 1) — é DDI de outro país já embutido (ex.: EUA/
  -- Canadá, "1" + DDD(3) + número(7) = 11). Não atropelar.
  if length(v) = 10 or (length(v) = 11 and left(v, 1) <> '1') then
    v := '55' || v;
  end if;

  -- com prefixo 55 + DDD (2) + número (8 ou 9) = 12 ou 13 dígitos:
  -- aplica a regra do nono dígito. Qualquer outro formato (ex.: ID de
  -- grupo, ou DDI de outro país, que não começa com 55) passa direto,
  -- sem tentar validar.
  if left(v, 2) = '55' and length(v) in (12, 13) then
    v_ddd := substring(v from 3 for 2)::int;
    v_resto := substring(v from 5);

    if v_ddd >= 31 and length(v_resto) = 9 and left(v_resto, 1) = '9' then
      v_resto := substring(v_resto from 2);
      v := '55' || lpad(v_ddd::text, 2, '0') || v_resto;
    end if;
  end if;

  return v;
end;
$$;

revoke all on function hub.fone_norm(text) from public, anon;
grant execute on function hub.fone_norm(text) to authenticated, service_role;
