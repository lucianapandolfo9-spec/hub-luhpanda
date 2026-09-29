-- ============================================================
-- HUB LUH PANDA — 035: o recebível futuro acompanha o valor do contrato
-- (e o valor editado à mão fica travado)
--
-- O BUG (reproduzido em produção em 28/09/2026 e corrigido na mão direto no
-- banco naquele dia, sem consertar a causa): contrato de teste de R$1,00 virou
-- R$1.200 → Out/26 e Nov/26 continuaram R$1,00 na tela Recebíveis.
--
-- ⚠️ A sessão de 28/09 registrou "race condition no salvar". ESTÁ ERRADO, e
-- fica escrito aqui pra essa hipótese não voltar como verdade: o front está
-- certo (o `await` do upsert do contrato acontece ANTES da geração, e a RPC lê
-- o valor direto de `hub.contratos` — não recebe valor por parâmetro). O
-- defeito é todo SQL:
--
--   `hub.rpc_garantir_recebiveis_mes` (034) é INSERT-only e idempotente por
--   EXISTÊNCIA: se já existe recebível daquele cliente naquela competência ela
--   faz `continue` — nunca compara, nunca atualiza. Contrato muda, recebível
--   não acompanha. Nunca houve race condition.
--
-- Mais três defeitos irmãos na mesma função, achados junto (034:140-154):
--   • dedupe por `cliente_id` + `origem`, SEM `contrato_id` — cliente com dois
--     contratos ativos gera um recebível só por mês, pra sempre;
--   • `count(*) where contrato_id = X` conta recebível de QUALQUER competência,
--     inclusive as futuras que o próprio front pré-aquece — a numeração
--     "parcela N/total" pula e o parcelamento encerra cedo (já visível em
--     produção: The Best com parcelas_total=6 e Nov/Dez/Jan sem numeração);
--   • a trava de `inicio_em` não pega em contrato novo, porque `inicio_em`
--     nasce NULL desde o D1.1 (o campo saiu da tela).
--
-- AS DECISÕES QUE MANDAM AQUI (dela, 29/09/2026 — reler antes de mexer nesta
-- função de novo):
--
--   1) O CONTRATO É A FONTE DA VERDADE dos meses NÃO PAGOS do mês corrente pra
--      frente — mas um valor que ela digitou na tela vence o contrato e fica
--      TRAVADO (`valor_travado`); a geração automática nunca mais encosta nele.
--      Sem essa trava, "sincronizar" viraria o sistema escrevendo por cima do
--      que ela decidiu — bug pior do que o que estamos consertando.
--   2) RECEBÍVEL PAGO É FATO CONSUMADO: `entrada_centavos > 0` ou
--      `entrou_em is not null` = intocável, em qualquer circunstância.
--      (Lembrete: NÃO existe coluna `status` em hub.recebiveis — "pago" é
--      exatamente essa dupla de colunas.)
--   3) O PASSADO NÃO SE REESCREVE: o reajuste tem piso no mês corrente
--      (America/Recife), mesmo que a RPC seja chamada pra um mês anterior.
--   4) NUNCA MEXER NA `descricao` de um recebível que já existe — o texto é
--      dela (ex.: "Pagamento parcelas Fase 01" no Out/26 do The Best). Esta
--      função só escreve valor.
--   5) NA DÚVIDA, FALTAR UMA LINHA É MELHOR DO QUE COBRAR EM DOBRO — é por isso
--      que o caso ambíguo de recebível legado (sem `contrato_id`) recua sem
--      criar nada, em vez de "adotar no chute".
--
-- Efeito colateral bom: `hub.recebiveis` já tem `trg_recebiveis_auditoria`
-- (AFTER INSERT/UPDATE/DELETE → hub.registrar_auditoria), então todo UPDATE de
-- valor que esta função passa a fazer já nasce auditado, com antes/depois. Não
-- precisa de log novo. É também por isso que o `is distinct from` do reajuste
-- NÃO é estilo, é obrigatório: um UPDATE incondicional a cada render encheria
-- `hub.eventos_auditoria` de lixo e quebraria a idempotência.
--
-- O retorno continua `int` DE PROPÓSITO (não virou jsonb): mudar o shape
-- obrigaria a dropar o wrapper `public.hub_rpc_garantir_recebiveis_mes` em
-- produção na véspera de uma apresentação, risco desnecessário. O que muda é o
-- SIGNIFICADO: agora é "linhas tocadas" = criados + reajustados.
--
-- ⚠️ NÃO APLICADA por esta sessão de dev — por instrução dela: ela revisa e
-- aplica pelo MCP. Ao aplicar:
--   1) `apply_migration`;
--   2) `get_advisors` (security) depois;
--   3) testar com CLIENTE DESCARTÁVEL (nunca um dos 8 reais) — roteiro no
--      rodapé deste arquivo;
--   4) rodar duas vezes seguidas: a segunda tem que voltar 0. Se oscilar, tem
--      bug.
-- ============================================================


-- ============================================================
-- 0) pré-requisitos — falha cedo e com mensagem legível
-- ============================================================

do $$
begin
  if to_regclass('hub.contratos') is null then
    raise exception 'hub.contratos não existe — aplicar a 002 antes da 035.';
  end if;
  if to_regclass('hub.recebiveis') is null then
    raise exception 'hub.recebiveis não existe — conferir manualmente antes de seguir (ver nota no topo da 006).';
  end if;
  if not exists (
    select 1 from pg_attribute
    where attrelid = 'hub.recebiveis'::regclass
      and attname = 'contrato_id' and not attisdropped
  ) then
    raise exception 'hub.recebiveis.contrato_id não existe — aplicar a 034 antes da 035.';
  end if;
end $$;

-- `hub.rpc_salvar_recebivel(jsonb)` NUNCA esteve em migration nenhuma deste
-- repo — vive só dentro do banco desde a Fase 2. O bloco 3 abaixo recria essa
-- função a partir do corpo lido do banco em 29/09/2026, mudando SÓ o que é de
-- `valor_travado`. Estes dois guards existem pra que a 035 não apague nada que
-- eu não tenha visto:
--   • retorno diferente de uuid → `create or replace` estouraria erro críptico;
--   • guard `is_admin()` no corpo atual → o corpo do bloco 3 TEM esse guard
--     (conferido por introspecção em 29/09). Se a função no banco não tiver, a
--     forma dela divergiu do que esta migration assume — parar e reconciliar
--     antes de sobrescrever.
-- Se qualquer um dos dois disparar: rodar
--   select pg_get_functiondef('hub.rpc_salvar_recebivel(jsonb)'::regprocedure);
-- e reconciliar o bloco 3 com o que estiver lá ANTES de aplicar.
do $$
declare v_ret text; v_src text;
begin
  select pg_get_function_result(p.oid), p.prosrc into v_ret, v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'hub' and p.proname = 'rpc_salvar_recebivel'
    and pg_get_function_identity_arguments(p.oid) = 'p jsonb';

  if v_ret is null then
    raise exception 'hub.rpc_salvar_recebivel(jsonb) não existe no banco — conferir antes de seguir.';
  end if;
  if v_ret <> 'uuid' then
    raise exception 'hub.rpc_salvar_recebivel(jsonb) retorna "%", e o bloco 3 desta migration assume uuid — reconciliar antes de aplicar.', v_ret;
  end if;
  if v_src not like '%is_admin%' then
    raise exception 'hub.rpc_salvar_recebivel(jsonb) NÃO tem guard is_admin() no banco — a forma dela divergiu do que a 035 assume. Reconciliar com pg_get_functiondef antes de sobrescrever.';
  end if;
end $$;


-- ============================================================
-- 1) coluna nova (a trava) + índice único (a rede de proteção)
-- ============================================================

alter table hub.recebiveis
  add column if not exists valor_travado boolean not null default false;

comment on column hub.recebiveis.valor_travado is
  'true = valor editado à mão pela tela; a geração automática nunca sobrescreve (migration 035). Fica true sozinho quando hub.rpc_salvar_recebivel recebe um valor diferente do que estava gravado, e não volta pra false sozinho: destravar é decisão dela, mandando valor_travado=false explícito no payload. Default false — nenhum recebível que já existia muda de comportamento ao aplicar a migration.';

-- Rede de proteção pro pior desfecho possível deste código: cobrar a mesma
-- competência duas vezes no mesmo contrato. A partir daqui isso vira erro de
-- banco, não linha a mais na tela dela.
-- ⚠️ `competencia::timestamp` (e não timestamptz) de propósito: só a versão
-- timestamp de date_trunc é IMMUTABLE, que é o que índice de expressão exige.
-- Pré-checagem de duplicata já rodada em 29/09/2026: zero linhas (query no
-- rodapé do arquivo, pra repetir se um dia isso falhar).
create unique index if not exists uq_recebiveis_contrato_mes
  on hub.recebiveis (contrato_id, (date_trunc('month', competencia::timestamp)::date))
  where contrato_id is not null;


-- ============================================================
-- 2) hub.rpc_garantir_recebiveis_mes — agora também REAJUSTA
-- ============================================================
--
-- Continua chamada pelo front (tela Financeiro e ao salvar contrato ativo),
-- continua idempotente, continua `returns int`. Duas coisas novas por contrato:
--   A) criação do mês pedido, com numeração de parcela estável;
--   B) reajuste em massa de TODOS os meses daquele contrato do piso pra frente
--      — não só do mês pedido. Sem isso, Fev/Mar de 2027 (que já existem no
--      banco) nunca seriam corrigidos, porque o front só pede 3 meses.

create or replace function hub.rpc_garantir_recebiveis_mes(p_competencia date)
returns int
language plpgsql security definer set search_path = pg_catalog
as $$
declare
  v_comp date;
  v_hoje date;
  v_piso date;
  v_ultimo_dia date;
  rec record;
  v_ja_existe boolean;
  v_legado_n int;
  v_legado_id uuid;
  v_base date;
  v_parcela_num int;
  v_descricao text;
  v_vence date;
  v_n int;
  v_criados int := 0;
  v_ajustados int := 0;
begin
  if not hub.is_admin() then raise exception 'acesso negado'; end if;
  if p_competencia is null then raise exception 'competência é obrigatória'; end if;

  v_comp := date_trunc('month', p_competencia)::date;
  v_ultimo_dia := (v_comp + interval '1 month - 1 day')::date;

  -- decisão 3 do topo: o reajuste nunca desce abaixo do mês corrente, mesmo se
  -- alguém chamar a RPC pra um mês passado. Fuso dela, não o do servidor.
  v_hoje := (now() at time zone 'America/Recife')::date;
  v_piso := greatest(v_comp, date_trunc('month', v_hoje)::date);

  for rec in
    select ct.id as contrato_id, ct.cliente_id, ct.valor_mensal_centavos,
           ct.dia_vencimento, ct.parcelas_total, ct.inicio_em,
           count(*) over (partition by ct.cliente_id) as contratos_do_cliente
    from hub.contratos ct
    join hub.clientes cl on cl.id = ct.cliente_id
    where ct.status = 'ativo'
      and ct.recorrencia_ativa
      and ct.valor_mensal_centavos is not null
      and coalesce(cl.recorrente, true) is not false
    order by ct.id  -- ordem estável: idempotência não pode depender do plano
  loop

    -- ---------- A) criação do mês pedido ----------

    select exists (
      select 1 from hub.recebiveis r
      where r.contrato_id = rec.contrato_id
        and date_trunc('month', r.competencia)::date = v_comp
    ) into v_ja_existe;

    if not v_ja_existe then
      -- LEGADO = recebível de contrato lançado à mão antes da 034, sem
      -- `contrato_id` (em produção: os de Set/26). Se eu ignorar isso e criar,
      -- a linha nasce duplicada na tela e ela cobra duas vezes.
      -- ⚠️ `(array_agg(id order by id))[1]` e NÃO `min(id)`: o Postgres não tem
      -- agregado min/max pra uuid (confirmado no PG 17.6 em 29/09 — a 035
      -- estourou "function min(uuid) does not exist" no primeiro teste).
      select count(*), (array_agg(r.id order by r.id))[1] into v_legado_n, v_legado_id
      from hub.recebiveis r
      where r.cliente_id = rec.cliente_id
        and r.origem = 'contrato'
        and r.contrato_id is null
        and date_trunc('month', r.competencia)::date = v_comp;

      if v_legado_n = 1 and rec.contratos_do_cliente = 1 then
        -- um órfão, um contrato: a adoção é certa, não é chute. Amarra, e a
        -- partir daí ele entra na conta de parcelas e para de ser reencontrado.
        -- Não conta como "linha tocada" no retorno de propósito: o retorno é
        -- criados + reajustados, e adoção não é nem um nem outro.
        update hub.recebiveis set contrato_id = rec.contrato_id where id = v_legado_id;

      elsif v_legado_n > 0 then
        -- Ambíguo: mais de um órfão no mês, ou mais de um contrato ativo do
        -- mesmo cliente. Não dá pra saber de qual contrato o órfão é. RECUA:
        -- não adota, não insere, não duplica (decisão 5 do topo). Caso real:
        -- The Best tem 2 legados em Set/26.
        null;

      else
        -- Numeração de parcela por DISTÂNCIA DE MESES a partir de uma base
        -- estável, não por `count(*)` (que era o defeito 3: um lançamento
        -- manual em mês anterior deslocava toda a numeração). Base, na ordem:
        -- início do contrato → primeiro recebível já existente dele → o próprio
        -- mês pedido (contrato novo, `inicio_em` nulo desde o D1.1).
        -- Conferido contra os dados reais: Daniel Magnus segue Out/26 = 2/6 …
        -- Fev/27 = 6/6, e Mar/27 daria 7 > 6 → para. Nada já existente renumera.
        v_base := date_trunc('month', coalesce(
                    rec.inicio_em,
                    (select min(r.competencia) from hub.recebiveis r
                      where r.contrato_id = rec.contrato_id),
                    v_comp))::date;

        v_parcela_num := ((extract(year from v_comp)::int * 12 + extract(month from v_comp)::int)
                        - (extract(year from v_base)::int * 12 + extract(month from v_base)::int)) + 1;

        -- `v_parcela_num < 1` = mês anterior ao início do contrato (é o que
        -- substitui a trava de `inicio_em` da 034, defeito 4).
        -- `> parcelas_total` = parcelamento encerrado — não vira mensalidade
        -- infinita. Nos dois casos só a CRIAÇÃO é pulada; o reajuste do bloco B
        -- continua rodando, senão um contrato que acabou de encerrar as
        -- parcelas deixaria de corrigir os meses já criados.
        if v_parcela_num >= 1
           and (rec.parcelas_total is null or v_parcela_num <= rec.parcelas_total)
        then
          select ci.descricao into v_descricao
          from hub.contrato_itens ci
          where ci.contrato_id = rec.contrato_id
          order by ci.created_at asc
          limit 1;
          if v_descricao is null or btrim(v_descricao) = '' then
            v_descricao := 'Mensalidade';
          end if;
          if rec.parcelas_total is not null then
            v_descricao := v_descricao || ' — parcela ' || v_parcela_num || '/' || rec.parcelas_total;
          end if;

          v_vence := case when rec.dia_vencimento is not null
            then make_date(
              extract(year from v_comp)::int, extract(month from v_comp)::int,
              least(rec.dia_vencimento::int, extract(day from v_ultimo_dia)::int)
            )
            else null end;

          insert into hub.recebiveis
            (cliente_id, contrato_id, competencia, descricao, valor_centavos, vence_em, origem)
          values
            (rec.cliente_id, rec.contrato_id, v_comp, v_descricao, rec.valor_mensal_centavos, v_vence, 'contrato');

          v_criados := v_criados + 1;
        end if;
      end if;
    end if;

    -- ---------- B) reajuste em massa — o conserto do bug ----------
    --
    -- Um UPDATE só, cobrindo TODOS os meses desse contrato do piso pra frente
    -- (não só o mês pedido) — é o que alcança Fev/Mar de 2027, que já existem e
    -- que o front, pedindo 3 meses, nunca revisitaria.
    -- Cada condição do WHERE tem dono:
    --   contrato_id      → só o que nasceu deste contrato
    --   origem           → extra/aula/comissão não pertencem ao contrato
    --   >= v_piso        → decisão 3 (o passado não se reescreve)
    --   não pago         → decisão 2 (fato consumado)
    --   not valor_travado→ decisão 1 (a mão dela manda mais que o contrato)
    --   is distinct from → idempotência + não poluir a auditoria
    -- `descricao` fica de fora (decisão 4). `sincronizado_planilha=false` porque
    -- o valor mudou e o espelho da planilha precisa reenviar.
    update hub.recebiveis r
       set valor_centavos = rec.valor_mensal_centavos,
           sincronizado_planilha = false
     where r.contrato_id = rec.contrato_id
       and r.origem = 'contrato'
       and date_trunc('month', r.competencia)::date >= v_piso
       and coalesce(r.entrada_centavos, 0) = 0
       and r.entrou_em is null
       and not r.valor_travado
       and r.valor_centavos is distinct from rec.valor_mensal_centavos;

    get diagnostics v_n = row_count;
    v_ajustados := v_ajustados + v_n;

  end loop;

  -- "linhas tocadas" — o front soma isso nos 3 meses que pede e avisa na tela.
  return v_criados + v_ajustados;
end;
$$;

revoke all on function hub.rpc_garantir_recebiveis_mes(date) from public, anon;
grant execute on function hub.rpc_garantir_recebiveis_mes(date) to authenticated;

-- Wrapper: shape idêntico ao de hoje (int), então `create or replace` basta —
-- nada de `drop function` em produção por causa desta migration.
create or replace function public.hub_rpc_garantir_recebiveis_mes(p_competencia date)
returns int
language sql security invoker set search_path = pg_catalog
as $$ select hub.rpc_garantir_recebiveis_mes(p_competencia); $$;

revoke all on function public.hub_rpc_garantir_recebiveis_mes(date) from public, anon;
grant execute on function public.hub_rpc_garantir_recebiveis_mes(date) to authenticated;


-- ============================================================
-- 3) hub.rpc_salvar_recebivel — marca (e destrava) a trava
-- ============================================================
--
-- Corpo idêntico ao que está no banco hoje (lido em 29/09/2026 — esta RPC nunca
-- esteve em migration nenhuma deste repo), com UMA mudança: `valor_travado`.
-- É isso que faz a decisão 1 do topo funcionar de verdade — sem esta parte, o
-- reajuste do bloco 2 passaria por cima do valor que ela acabou de digitar.
--
-- Armadilha conhecida deste upsert (023/025/032/034): ele é DESTRUTIVO, escreve
-- todas as colunas listadas. `contrato_id` continua FORA do `do update set` de
-- propósito — é assim que o vínculo se preserva quando ela edita um recebível
-- gerado automaticamente. Não acrescentar `contrato_id` aqui sem plano: editar
-- um recebível pela tela zeraria o vínculo e a contagem de parcelas recomeçaria.
-- `entrada_centavos`/`entrou_em` também ficam de fora (quem mexe neles é o
-- marcar/desmarcar pago) — é o que preserva o pagamento quando ela só corrige a
-- descrição de um mês já pago.

create or replace function hub.rpc_salvar_recebivel(p jsonb)
returns uuid
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_id uuid;
begin
  -- 29/09: confirmado por introspecção que a versão em produção TEM este guard.
  -- Sem ele, qualquer usuário `authenticated` escreveria recebível de qualquer
  -- cliente. Nunca remover ao recriar esta função.
  if not hub.is_admin() then raise exception 'acesso negado'; end if;

  insert into hub.recebiveis (id, cliente_id, competencia, descricao, valor_centavos, entrada_centavos, entrou_em, vence_em, origem, observacao, valor_travado)
  values (coalesce((p->>'id')::uuid, gen_random_uuid()), (p->>'cliente_id')::uuid, (p->>'competencia')::date, p->>'descricao', (p->>'valor_centavos')::bigint, coalesce((p->>'entrada_centavos')::bigint, 0), (p->>'entrou_em')::date, (p->>'vence_em')::date, coalesce(p->>'origem','contrato'), p->>'observacao', coalesce((p->>'valor_travado')::boolean, false))
  on conflict (id) do update set
    cliente_id=excluded.cliente_id, competencia=excluded.competencia, descricao=excluded.descricao,
    valor_centavos=excluded.valor_centavos, vence_em=excluded.vence_em, origem=excluded.origem,
    observacao=excluded.observacao, sincronizado_planilha=false,
    -- 035, nesta ordem de precedência:
    --   1. veio `valor_travado` no payload → manda ele (é assim que ela
    --      DESTRAVA um mês de propósito: valor_travado=false explícito);
    --   2. senão, mudou o valor pela tela → trava;
    --   3. senão, fica como estava — salvar só a observação não destrava nada.
    valor_travado = case
      when p ? 'valor_travado' then coalesce((p->>'valor_travado')::boolean, false)
      when hub.recebiveis.valor_centavos is distinct from excluded.valor_centavos then true
      else hub.recebiveis.valor_travado
    end
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function hub.rpc_salvar_recebivel(jsonb) from public, anon;
grant execute on function hub.rpc_salvar_recebivel(jsonb) to authenticated;

-- O wrapper public.hub_rpc_salvar_recebivel(jsonb) NÃO é recriado aqui: nem a
-- assinatura nem o retorno mudaram, então o que já existe continua valendo.


-- ============================================================
-- Conferência — antes e depois de aplicar
-- ============================================================
--
-- PRÉ-CHECAGEM do índice único (rodada em 29/09/2026 → zero linhas; repetir se
-- a criação do índice falhar, o resultado diz exatamente qual contrato/mês
-- está duplicado):
--   select contrato_id, date_trunc('month', competencia)::date as mes, count(*)
--   from hub.recebiveis where contrato_id is not null
--   group by 1,2 having count(*) > 1;
--
-- FOTO DE ANTES (guardar a saída pra comparar depois — os 8 reais não podem
-- mudar de valor por efeito colateral):
--   select c.nome, r.competencia, r.valor_centavos, r.contrato_id, r.entrou_em
--   from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
--   where r.origem = 'contrato' order by r.competencia, c.nome;
--
-- DEPOIS, com CLIENTE DESCARTÁVEL (nunca um dos 8 reais):
--   -- contrato ativo R$100, 3 parcelas, dia 10
--   select hub_rpc_garantir_recebiveis_mes('2026-10-01');  -- 1  (criou)
--   select hub_rpc_garantir_recebiveis_mes('2026-10-01');  -- 0  ← idempotência
--   select hub_rpc_garantir_recebiveis_mes('2026-11-01');  -- 1
--   select hub_rpc_garantir_recebiveis_mes('2026-12-01');  -- 1
--   select hub_rpc_garantir_recebiveis_mes('2027-01-01');  -- 0  (4/3 não existe)
--   -- muda o contrato pra R$250 e roda UMA vez:
--   select hub_rpc_garantir_recebiveis_mes('2026-10-01');  -- 3  ← Out, Nov E Dez
--   select competencia, descricao, valor_centavos, valor_travado, entrada_centavos, entrou_em
--   from hub.recebiveis where contrato_id = '<uuid-do-contrato-de-teste>' order by competencia;
--   -- trava: salvar o recebível pela tela com outro valor → valor_travado=true
--   --        → mudar o contrato de novo → esse mês não se mexe.
--   -- pago:  marcar um mês como pago → mudar o contrato → esse mês não se mexe.
--   -- descrição: nenhuma descrição já existente pode ter mudado.
--   -- apagar o cliente de teste inteiro ao final.
--
-- LEGADO em produção (deve ganhar contrato_id na primeira rodada, sem mudar de
-- valor, porque está pago — e The Best, com 2 órfãos em Set/26, deve continuar
-- exatamente como está, sem linha nova):
--   select c.nome, r.competencia, r.valor_centavos, r.contrato_id, r.entrou_em
--   from hub.recebiveis r join hub.clientes c on c.id = r.cliente_id
--   where r.origem = 'contrato' and r.competencia = '2026-09-01' order by c.nome;
-- ============================================================
