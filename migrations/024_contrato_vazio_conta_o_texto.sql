-- ============================================================
-- HUB LUH PANDA — 024: a guarda de contrato vazio passa a contar o texto
--
-- A guarda `hub_contrato_vazio_nao_cria` nasceu na 021 exigindo
-- `numero` OU `valor_mensal_centavos` OU `dia_vencimento`. Fazia sentido
-- naquele momento: o form tinha 8 campos e `numero` era o primeiro deles.
--
-- O D1.1 mudou o terreno. O formulário virou UMA caixa de texto grande + 3
-- controles (valor, dia, status); `numero` saiu da tela e o texto livre —
-- gravado em `observacao` — virou o campo principal, que é exatamente o
-- fluxo que ela pediu ("escrever tudo de uma vez numa caixa só").
--
-- Resultado: contrato escrito SÓ em texto livre, sem valor e sem dia, batia
-- na guarda. A guarda existia pra barrar "abri o modal e salvei sem querer",
-- não pra exigir valor — e ela passou a barrar o caminho feliz.
--
-- Correção: recusar só quando OS QUATRO estiverem vazios. Um contrato com
-- texto escrito nunca mais é "vazio". A mensagem do front
-- ("preencha pelo menos o valor mensal ou o dia de vencimento") volta a ser
-- verdade, porque agora ela só aparece com a caixa de texto vazia também.
--
-- A 021 NÃO é editada — já está aplicada em produção. `create or replace`
-- aqui, que é o que vale pra função de shape estável (retorna uuid), então o
-- wrapper público da 004 continua válido sem recriação.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev (separação de papéis: quem coda não
-- aplica). Aplicar com `apply_migration` e rodar `get_advisors` depois.
-- ============================================================

create or replace function hub.rpc_salvar_contrato(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  -- Vale SÓ pro INSERT (payload sem `id`). UPDATE continua livre — esvaziar
  -- um contrato que já existe é decisão dela, não acidente.
  if (p->>'id') is null
     and nullif(btrim(coalesce(p->>'numero','')), '') is null
     and nullif(btrim(coalesce(p->>'valor_mensal_centavos','')), '') is null
     and nullif(btrim(coalesce(p->>'dia_vencimento','')), '') is null
     and nullif(btrim(coalesce(p->>'observacao','')), '') is null   -- ← 024: o texto conta
  then
    -- nome de erro estável, no estilo de hub_contrato_ativo_exige_porta_saida,
    -- pro front traduzir em friendlyError()
    raise exception 'hub_contrato_vazio_nao_cria';
  end if;

  insert into hub.contratos (id, cliente_id, numero, status, inicio_em, fim_minimo_em, dia_vencimento, valor_mensal_centavos, porta_saida_tipo, porta_saida_valor_centavos, porta_saida_escrita_em, observacao)
  values (
    coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, p->>'numero',
    coalesce(p->>'status','rascunho'), (p->>'inicio_em')::date, (p->>'fim_minimo_em')::date,
    (p->>'dia_vencimento')::smallint, (p->>'valor_mensal_centavos')::bigint, p->>'porta_saida_tipo',
    (p->>'porta_saida_valor_centavos')::bigint, (p->>'porta_saida_escrita_em')::timestamptz, p->>'observacao'
  )
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, numero=excluded.numero, status=excluded.status, inicio_em=excluded.inicio_em,
    fim_minimo_em=excluded.fim_minimo_em, dia_vencimento=excluded.dia_vencimento, valor_mensal_centavos=excluded.valor_mensal_centavos,
    porta_saida_tipo=excluded.porta_saida_tipo, porta_saida_valor_centavos=excluded.porta_saida_valor_centavos,
    porta_saida_escrita_em=excluded.porta_saida_escrita_em, observacao=excluded.observacao
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_contrato(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_contrato(jsonb) to authenticated;

-- Conferência depois de aplicar (as duas rodam como admin, na ficha de um
-- cliente qualquer — apagar o contrato de teste depois):
--   • só texto           → deve GRAVAR
--   • tudo vazio, sem id → deve levantar hub_contrato_vazio_nao_cria
