import { createOpencodeClient } from "@opencode-ai/sdk";
import process from "node:process";

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) return "";
  return Buffer.concat(chunks).toString("utf8");
};

const unwrapData = (value) => value?.data ?? value;

const normalizeModel = (model) => {
  if (!model) return null;
  if (typeof model === "string") {
    const slashIndex = model.indexOf("/");
    if (slashIndex > 0) {
      return {
        providerID: model.slice(0, slashIndex),
        modelID: model.slice(slashIndex + 1),
      };
    }
    return { modelID: model };
  }
  return model;
};

const extractText = (result) => {
  const data = unwrapData(result) ?? {};
  const parts = Array.isArray(data.parts) ? data.parts : [];
  const textParts = parts
    .filter((part) => part && part.type === "text" && typeof part.text === "string")
    .map((part) => part.text);
  if (textParts.length > 0) return textParts.join("\n");
  if (typeof data.text === "string") return data.text;
  if (typeof data.content === "string") return data.content;
  if (typeof data.message === "string") return data.message;
  return "";
};

const main = async () => {
  const rawInput = await readStdin();
  const input = rawInput ? JSON.parse(rawInput) : {};

  const baseUrl = input.baseUrl || "http://localhost:4096";
  const client = createOpencodeClient({ baseUrl });

  let sessionId = input.sessionId || null;
  if (!sessionId) {
    const sessionResult = await client.session.create({
      body: { title: input.sessionTitle || "Neovim" },
    });
    const sessionData = unwrapData(sessionResult) ?? {};
    sessionId = sessionData.id || null;
  }

  if (!sessionId) {
    throw new Error("Failed to resolve session id");
  }

  const promptText = typeof input.prompt === "string" ? input.prompt : "";
  const body = {
    parts: [{ type: "text", text: promptText }],
  };

  const model = normalizeModel(input.model);
  if (model) body.model = model;
  if (input.noReply) body.noReply = true;

  const result = await client.session.prompt({
    path: { id: sessionId },
    body,
  });

  if (result?.error) {
    throw new Error(result.error.message || "Opencode request failed");
  }

  const text = input.noReply ? "" : extractText(result);

  process.stdout.write(
    JSON.stringify({ ok: true, sessionId, text })
  );
};

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stdout.write(JSON.stringify({ ok: false, error: message }));
  process.exitCode = 1;
});
