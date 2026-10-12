// HUB LUH PANDA — docuseal-integrar/falhas.ts
//
// Leitura das respostas do DocuSeal, isolada do handler pra ser testável em
// Node (tests/edge-admin/docuseal-falhas.test.mjs). Nada aqui toca rede nem
// secret: recebe status/corpo e devolve explicação.
//
// CAUSA RAIZ DO 502 DE 08/10/2026 (conferida no código-fonte do DocuSeal,
// tag 3.2.6 = a versão do self-host, e por sonda HTTP sem token):
// a edição gratuita (open source) do DocuSeal NÃO TEM a rota
// POST /api/submissions/html. Ela só expõe, na API:
//   /api/submissions (com template_id), /api/templates/:id (sem criar),
//   /api/templates/:id/clone, /api/submitters, /api/user, /api/tools.
// As rotas /submissions/html, /submissions/pdf, /templates/html,
// /templates/pdf e /templates/docx são da nuvem/Pro. No self-host gratuito
// a rota inexistente devolve 404 ANTES de checar o token — por isso o 502
// aconteceu mesmo com a chave possivelmente certa.

export const ROTA_ENVIO_HTML = "/api/submissions/html";

const LIMITE_CORPO = 300;

// corta e tira quebras de linha; o corpo de erro do DocuSeal nunca traz o
// token, mas o corte evita despejar HTML de página 404 inteira no log.
export function resumirCorpo(texto: string | null | undefined): string {
  if (!texto) return "";
  const limpo = String(texto).replace(/\s+/g, " ").trim();
  return limpo.length > LIMITE_CORPO ? limpo.slice(0, LIMITE_CORPO) + "…" : limpo;
}

export type Explicacao = { causa: string; acao: string };

export function explicarFalhaDocuseal(status: number | null, rota: string = ROTA_ENVIO_HTML): Explicacao {
  if (status === null) {
    return {
      causa: "o DocuSeal não respondeu (rede/DNS/timeout).",
      acao: "Conferir se https://assinar.luhpanda.com.br abre e tentar de novo.",
    };
  }
  if (status === 404 && rota === ROTA_ENVIO_HTML) {
    return {
      causa: "este DocuSeal (self-host, edição gratuita) não tem o recurso de criar envelope a partir do HTML do contrato — essa rota só existe na nuvem/Pro do DocuSeal.",
      acao: "Decisão da Luciana: (1) licença Pro do self-host, (2) API da nuvem do DocuSeal, ou (3) modelo fixo criado no painel do DocuSeal. Ver nota do Hub Dev de 08/10/2026.",
    };
  }
  if (status === 401 || status === 403) {
    return {
      causa: "o DocuSeal recusou a chave de API (DOCUSEAL_API_KEY) — ela pode ter sido gerada em outra instância (ex.: console.docuseal.com) ou revogada.",
      acao: "Gerar a chave em https://assinar.luhpanda.com.br/settings/api (logada no self-host) e colar no secret DOCUSEAL_API_KEY do Supabase.",
    };
  }
  if (status === 402) {
    return {
      causa: "o DocuSeal exige plano pago pra este recurso.",
      acao: "Decisão da Luciana sobre plano (ver nota do Hub Dev de 08/10/2026).",
    };
  }
  if (status === 422 || status === 400) {
    return {
      causa: "o DocuSeal recusou o conteúdo enviado (formato do envelope).",
      acao: "Ler o corpo do erro no log da função docuseal-integrar e ajustar o payload.",
    };
  }
  if (status >= 500) {
    return {
      causa: "o DocuSeal deu erro interno.",
      acao: "Olhar os logs do container do DocuSeal na VPS.",
    };
  }
  return { causa: `o DocuSeal respondeu ${status}.`, acao: "Ler o corpo do erro no log da função." };
}

// Diagnóstico sem efeito colateral (não cria envelope, não manda e-mail).
// `statusChave`: GET /api/user COM a chave → 200 = chave é desta instância.
// `statusRotaHtml`: POST /api/submissions/html SEM chave e corpo {} →
//   404 = rota não existe nesta edição; 401 = rota existe (Pro/nuvem).
export function concluirDiagnostico(d: {
  versao: string | null;
  statusChave: number | null;
  statusRotaHtml: number | null;
}) {
  const chaveValida = d.statusChave === 200;
  const rotaHtmlExiste = d.statusRotaHtml !== null && d.statusRotaHtml !== 404;
  const problemas: string[] = [];
  if (d.statusChave === null) problemas.push("DocuSeal fora do ar ou inacessível.");
  else if (!chaveValida) problemas.push(explicarFalhaDocuseal(d.statusChave, "/api/user").causa);
  if (d.statusRotaHtml !== null && !rotaHtmlExiste) problemas.push(explicarFalhaDocuseal(404).causa);
  return {
    versao: d.versao,
    chave: { status: d.statusChave, valida: chaveValida },
    envio_por_html: { status: d.statusRotaHtml, disponivel: rotaHtmlExiste },
    pronto_pra_enviar: chaveValida && rotaHtmlExiste,
    problemas,
  };
}
