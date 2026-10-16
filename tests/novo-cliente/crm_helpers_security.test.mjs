import { test } from "node:test";
import assert from "node:assert/strict";
import { database } from "./fixture.mjs";

test("helpers de lookup por telefone nao podem ser chamados diretamente por authenticated",async()=>{
  const {db}=await database(["migrations/20261015235000_crm_helpers_security.sql"]);
  const as=async(role,sql,email)=>db.transaction(async tx=>{
    const claims=role==="service_role"?{role}:{role,sub:"00000000-0000-4000-8000-00000000000a",email};
    await tx.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(claims)]);
    await tx.exec("set local role "+role);
    return (await tx.query(sql)).rows;
  });
  try {
    const commands=["select * from hub.crm_ids('5511999998888')","select hub.fone_no_crm('5511999998888')"];
    for(const sql of commands){
      await assert.rejects(as("authenticated",sql,"intruso@exemplo.test"),/permission denied|acesso negado/);
      await assert.rejects(as("authenticated",sql,"admin@hub.test"),/permission denied|acesso negado/);
      // Service role continua autorizado (ingestor n8n e funcao interna).
      assert.equal((await as("service_role",sql)).length,1);
    }
  } finally { await db.close(); }
});
