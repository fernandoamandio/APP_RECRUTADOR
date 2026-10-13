// Edge Function: analisa o currículo (PDF) e a cover letter do usuário com o Claude
// e grava o perfil profissional em career_profile para o usuário revisar no app.
//
// Chamada pelo app depois do upload:
//   POST /functions/v1/analyze-cv   { "cv_document_id": "...", "cover_letter_document_id": "..." | null }
//
// Segredos necessários: ANTHROPIC_API_KEY (supabase secrets set ...)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem no ambiente das Edge Functions.

import { createClient } from "npm:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const MODEL = Deno.env.get("CLAUDE_PROFILE_MODEL") ?? "claude-sonnet-5-5";
const MAX_PDF_BYTES = 10 * 1024 * 1024;

const PROFILE_TOOL = {
  name: "save_career_profile",
  description: "Salva o perfil profissional extraído do currículo.",
  input_schema: {
    type: "object",
    properties: {
      target_titles: {
        type: "array",
        items: { type: "string" },
        description: "Cargos-alvo e variações de título em inglês, português e espanhol, mais prováveis primeiro (máx. 8).",
      },
      seniority: { type: "string", enum: ["junior", "mid", "senior", "staff", "lead", "manager"] },
      years_total: { type: ["number", "null"], description: "Anos de experiência profissional na área, se dedutível." },
      stack: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            level: { type: "string", enum: ["main", "secondary", "basic"] },
            years: { type: ["number", "null"] },
          },
          required: ["name", "level"],
        },
      },
      domains: { type: "array", items: { type: "string" }, description: "Domínios de negócio (saúde, finanças...)." },
      languages: {
        type: "array",
        items: {
          type: "object",
          properties: {
            language: { type: "string" },
            level: { type: "string", enum: ["basic", "intermediate", "advanced", "fluent", "native"] },
          },
          required: ["language", "level"],
        },
      },
      keywords: {
        type: "object",
        properties: {
          search_terms: { type: "array", items: { type: "string" }, description: "Termos de busca em inglês para agregadores (máx. 6)." },
          remoteok_tags: { type: "array", items: { type: "string" }, description: "Tags curtas em minúsculas (ex.: oracle, sql)." },
        },
        required: ["search_terms", "remoteok_tags"],
      },
      strengths: { type: "array", items: { type: "string" }, description: "Até 4 pontos fortes para o mercado internacional." },
      gaps: { type: "array", items: { type: "string" }, description: "Até 4 lacunas do currículo com sugestão concreta de melhoria." },
    },
    required: ["target_titles", "seniority", "stack", "keywords", "strengths", "gaps"],
  },
};

const INSTRUCTIONS = `Você analisa currículos de profissionais brasileiros que buscam vagas remotas para empresas estrangeiras ou vagas com patrocínio de visto.
Extraia apenas o que está no documento. Não invente empresas, anos, certificações ou números.
Se algo não puder ser deduzido, deixe a lista vazia ou o campo como null.
Escreva strengths e gaps em português do Brasil, curtos e acionáveis.
Use a cover letter, se houver, apenas para entender motivações e tom; o perfil vem do currículo.
Responda chamando a ferramenta save_career_profile.`;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function downloadPdf(admin: ReturnType<typeof createClient>, path: string): Promise<string> {
  const { data, error } = await admin.storage.from("documents").download(path);
  if (error || !data) throw new Error(`falha ao baixar ${path}`);
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.byteLength > MAX_PDF_BYTES) throw new Error("PDF maior que 10 MB");
  return encodeBase64(bytes);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Identifica o usuário pelo JWT enviado pelo app
  const { data: userData, error: userErr } = await admin.auth.getUser(authHeader.replace("Bearer ", ""));
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  const { cv_document_id, cover_letter_document_id } = await req.json().catch(() => ({}));
  if (!cv_document_id) return json({ error: "cv_document_id obrigatório" }, 400);

  // LGPD: só analisa com consentimento registrado
  const { data: profile } = await admin.from("profiles").select("consent_ai_at").eq("user_id", userId).single();
  if (!profile?.consent_ai_at) return json({ error: "consentimento_ia_ausente" }, 403);

  const ids = [cv_document_id, cover_letter_document_id].filter(Boolean);
  const { data: docs, error: docsErr } = await admin
    .from("documents").select("id, kind, storage_path").in("id", ids).eq("user_id", userId);
  if (docsErr || !docs?.length) return json({ error: "documento não encontrado" }, 404);

  const cv = docs.find((d) => d.id === cv_document_id && d.kind === "cv");
  if (!cv) return json({ error: "currículo não encontrado" }, 404);
  const cover = docs.find((d) => d.id === cover_letter_document_id);

  const content: unknown[] = [
    { type: "document", source: { type: "base64", media_type: "application/pdf", data: await downloadPdf(admin, cv.storage_path) }, title: "Currículo" },
  ];
  if (cover) {
    content.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: await downloadPdf(admin, cover.storage_path) }, title: "Cover letter" });
  }
  content.push({ type: "text", text: "Extraia o perfil profissional destes documentos." });

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 2048,
      system: INSTRUCTIONS,
      tools: [PROFILE_TOOL],
      tool_choice: { type: "tool", name: PROFILE_TOOL.name },
      messages: [{ role: "user", content }],
    }),
  });
  if (!resp.ok) {
    console.error("anthropic_error", resp.status, await resp.text());
    return json({ error: "falha na análise" }, 502);
  }
  const result = await resp.json();
  const toolUse = result.content?.find((b: { type: string }) => b.type === "tool_use");
  if (!toolUse) return json({ error: "resposta sem perfil" }, 502);
  const p = toolUse.input;

  const { error: upErr } = await admin.from("career_profile").upsert({
    user_id: userId,
    target_titles: p.target_titles ?? [],
    seniority: p.seniority ?? null,
    years_total: p.years_total ?? null,
    stack: p.stack ?? [],
    domains: p.domains ?? [],
    keywords: p.keywords ?? {},
    strengths: p.strengths ?? [],
    gaps: p.gaps ?? [],
    source_doc_id: cv.id,
    confirmed_at: null, // o usuário precisa revisar de novo
    updated_at: new Date().toISOString(),
  });
  if (upErr) return json({ error: "falha ao salvar perfil" }, 500);

  // Idiomas encontrados no CV entram como sugestão (o usuário confirma no onboarding)
  if (Array.isArray(p.languages) && p.languages.length) {
    await admin.from("languages").upsert(
      p.languages.map((l: { language: string; level: string }) => ({ user_id: userId, ...l })),
      { onConflict: "user_id,language", ignoreDuplicates: true },
    );
  }

  return json({ profile: p });
});
