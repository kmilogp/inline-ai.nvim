import { ensureClient, readServerPassword } from "./opencode-server.ts";
import * as fs from "node:fs/promises";
import process from "node:process";
import { pathToFileURL } from "node:url";

type ClientInput = {
  baseUrl?: string;
  sessionId?: string | null;
  sessionTitle?: string;
  directory?: string;
  prompt?: string;
  model?: unknown;
  noReply?: boolean;
  serverConfigFile?: string;
  serverConfig?: Record<string, unknown>;
  debugLogFile?: string;
  createSession?: boolean;
  ensureServer?: boolean;
};

type PromptPart = { type: "text"; text: string };
type PromptBody = { parts: PromptPart[]; model?: unknown; noReply?: boolean };
type ClientDeps = {
  ensureClient?: typeof ensureClient;
  readServerPassword?: typeof readServerPassword;
  appendLog?: typeof appendLog;
  nowMs?: () => number;
};

const readStdin = async (): Promise<string> => {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  if (chunks.length === 0) return "";
  return Buffer.concat(chunks).toString("utf8");
};

const unwrapData = <T,>(
  value: T | { data?: T } | undefined | null
): T | undefined | null => ((value as any)?.data ?? value) as T | undefined | null;

const normalizeModel = (model: unknown): unknown => {
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

const extractText = (result: unknown): string => {
  const data = (unwrapData(result as any) ?? {}) as Record<string, unknown>;
  const parts = Array.isArray(data.parts) ? data.parts : [];
  const textParts = parts
    .filter((part: any) => part && part.type === "text" && typeof part.text === "string")
    .map((part: any) => part.text);
  if (textParts.length > 0) return textParts.join("\n");
  if (typeof data.text === "string") return data.text;
  if (typeof data.content === "string") return data.content;
  if (typeof data.message === "string") return data.message;
  return "";
};

const resolvePromptParts = (input: ClientInput): PromptPart[] => {
  const promptText = typeof input.prompt === "string" ? input.prompt : "";
  const parts: PromptPart[] = [{ type: "text", text: promptText }];
  return parts;
};

const appendLog = async (
  filePath: string | null | undefined,
  message: string,
  data?: Record<string, unknown>
): Promise<void> => {
  if (!filePath) return;
  const payload = data ? ` ${JSON.stringify(data)}` : "";
  const line = `${new Date().toISOString()} ${message}${payload}\n`;
  try {
    await fs.appendFile(filePath, line);
  } catch {
    // noop
  }
};

const nowMs = (): number => Date.now();

let debugLogFile: string | null = null;

const handleClientRequest = async (
  input: ClientInput,
  deps: ClientDeps = {}
): Promise<{
  ok: true;
  sessionId: string | null;
  text: string;
  serverStarted: boolean;
  sessionCreated: boolean;
}> => {
  const doAppendLog = deps.appendLog ?? appendLog;
  const getNow = deps.nowMs ?? nowMs;
  const doReadPassword = deps.readServerPassword ?? readServerPassword;
  const doEnsureClient = deps.ensureClient ?? ensureClient;

  debugLogFile = input.debugLogFile || null;

  const baseUrl = input.baseUrl || "http://localhost:4096";
  const directory = typeof input.directory === "string" ? input.directory : undefined;
  if (!input.serverConfigFile) {
    throw new Error("Missing server config file");
  }
  const startMs = getNow();
  const passwordStartMs = getNow();
  const password = await doReadPassword(input.serverConfigFile);
  await doAppendLog(debugLogFile, "timing.read_password", {
    ms: getNow() - passwordStartMs,
  });
  await doAppendLog(debugLogFile, "client.start", { baseUrl, directory });

  const ensureStartMs = getNow();
  const { client, startedServer } = await doEnsureClient(
    baseUrl,
    password,
    directory,
    input.serverConfig
  );
  await doAppendLog(debugLogFile, "timing.ensure_client", {
    ms: getNow() - ensureStartMs,
    startedServer: Boolean(startedServer),
  });
  await doAppendLog(debugLogFile, "server.ensure", { startedServer: Boolean(startedServer) });

  if (input.ensureServer) {
    return {
      ok: true,
      sessionId: input.sessionId ?? null,
      text: "",
      serverStarted: Boolean(startedServer),
      sessionCreated: false,
    };
  }

  let sessionId = input.sessionId || null;
  let sessionData: Record<string, any> | null = null;
  let sessionCreated = false;
  if (!sessionId) {
    const createStartMs = getNow();
    const sessionResult: any = await client.session.create({
      directory,
      title: input.sessionTitle || "Neovim",
    });
    await doAppendLog(debugLogFile, "timing.session_create", {
      ms: getNow() - createStartMs,
    });
    const sessionResultError = sessionResult?.error;
    if (sessionResultError) {
      const message =
        sessionResultError?.message ||
        sessionResultError?.error?.message ||
        sessionResultError?.errors?.[0]?.message ||
        JSON.stringify(sessionResultError);
      await doAppendLog(debugLogFile, "session.create.error", {
        message,
        baseUrl,
        directory,
      });
      throw new Error(`Failed to create session: ${message}`);
    }
    sessionData = (unwrapData(sessionResult) ?? {}) as Record<string, any>;
    sessionData = sessionData ?? {};
    const info = sessionData.info || sessionData.session || {};
    sessionId =
      sessionData.id ||
      sessionData.sessionId ||
      sessionData.sessionID ||
      sessionData.session_id ||
      info.id ||
      info.sessionId ||
      info.sessionID ||
      info.session_id ||
      null;
    sessionCreated = sessionId !== null;
  }

  if (!sessionId) {
    sessionData = sessionData ?? {};
    const info = sessionData.info || sessionData.session || {};
    const keys = Object.keys(sessionData).join(", ") || "none";
    const infoKeys = Object.keys(info).join(", ") || "none";
    await doAppendLog(debugLogFile, "session.create.missing_id", {
      keys,
      infoKeys,
      baseUrl,
      directory,
    });
    throw new Error(`Failed to resolve session id (keys: ${keys}; info: ${infoKeys})`);
  }

  let text = "";
  if (!input.createSession) {
    const body: PromptBody = {
      parts: resolvePromptParts(input),
    };

    if (!Array.isArray(body.parts)) {
      throw new Error("Prompt parts are missing or invalid");
    }

    const model = normalizeModel(input.model);
    if (model) body.model = model;
    if (input.noReply) body.noReply = true;

    const promptStartMs = getNow();
    const result: any = await client.session.prompt({
      sessionID: sessionId,
      directory,
      parts: body.parts,
      model: body.model,
      noReply: body.noReply,
    });
    await doAppendLog(debugLogFile, "timing.session_prompt", {
      ms: getNow() - promptStartMs,
    });

    const resultError = result?.error;
    if (resultError) {
      const message =
        resultError?.message ||
        resultError?.error?.message ||
        resultError?.errors?.[0]?.message ||
        JSON.stringify(resultError);
      await doAppendLog(debugLogFile, "session.prompt.error", {
        message,
        baseUrl,
        directory,
      });
      throw new Error(message || "Opencode request failed");
    }

    text = input.noReply ? "" : extractText(result);
  }

  await doAppendLog(debugLogFile, "timing.total", { ms: getNow() - startMs });
  return {
    ok: true,
    sessionId,
    text,
    serverStarted: Boolean(startedServer),
    sessionCreated,
  };
};

const main = async (): Promise<void> => {
  const rawInput = await readStdin();
  const input = (rawInput ? JSON.parse(rawInput) : {}) as ClientInput;
  const result = await handleClientRequest(input);
  process.stdout.write(JSON.stringify(result));
};

const isMain = (): boolean => {
  if (!process.argv[1]) return false;
  return pathToFileURL(process.argv[1]).href === import.meta.url;
};

if (isMain()) {
  main().catch((error) => {
    const message = error instanceof Error ? error.message : String(error);
    const raw = error instanceof Error ? error.stack : String(error);
    appendLog(debugLogFile, "client.error", { message, raw }).catch(() => {});
    process.stdout.write(JSON.stringify({ ok: false, error: message }));
    process.exitCode = 1;
  });
}

export { handleClientRequest };
