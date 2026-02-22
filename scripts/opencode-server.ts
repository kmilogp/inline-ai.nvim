import { createOpencode, createOpencodeClient } from "@opencode-ai/sdk/v2";
import * as crypto from "node:crypto";
import * as fs from "node:fs/promises";
import * as path from "node:path";

type EnsureClientResult = {
  client: any;
  startedServer: { close(): void } | null;
  startedInstance: { client: any; server: { close(): void } } | null;
};

const SERVER_USERNAME = "opencode";
const SERVER_START_RETRIES = 10;
const SERVER_START_DELAY_MS = 200;

const ensureDir = async (filePath: string): Promise<void> => {
  const dir = path.dirname(filePath);
  if (!dir) return;
  await fs.mkdir(dir, { recursive: true });
};

const generatePassword = (): string => crypto.randomBytes(24).toString("base64url");

const readServerPassword = async (filePath: string): Promise<string> => {
  if (!filePath) {
    throw new Error("Missing server password file path");
  }
  try {
    const content = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(content) as { password?: string };
    if (parsed && typeof parsed.password === "string" && parsed.password.trim() !== "") {
      return parsed.password.trim();
    }
  } catch (error) {
    const err = error as { code?: string };
    if (err?.code !== "ENOENT") {
      throw error;
    }
  }

  const password = generatePassword();
  await ensureDir(filePath);
  await fs.writeFile(filePath, JSON.stringify({ password }, null, 2), { mode: 0o600 });
  return password;
};

const createAuthFetch = (password: string) => {
  const token = Buffer.from(`${SERVER_USERNAME}:${password}`).toString("base64");
  return async (input: RequestInfo | URL, init: RequestInit = {}): Promise<Response> => {
    const headers = new Headers(init.headers || {});
    if (input instanceof Request) {
      input.headers.forEach((value, key) => {
        if (!headers.has(key)) {
          headers.set(key, value);
        }
      });
    }
    headers.set("Authorization", `Basic ${token}`);
    return fetch(input, { ...init, headers });
  };
};

const resolveServerConfig = (baseUrl: string) => {
  try {
    const url = new URL(baseUrl);
    const hostname = url.hostname || "127.0.0.1";
    const port = url.port ? Number(url.port) : 4096;
    return { hostname, port, baseUrl: url.toString() };
  } catch {
    return { hostname: "127.0.0.1", port: 4096, baseUrl: "http://localhost:4096" };
  }
};

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

const callHealth = async (client: any): Promise<any> => {
  if (client?.global?.health) {
    const result = await client.global.health();
    if (result?.error) {
      const message = result.error?.message || JSON.stringify(result.error);
      throw new Error(message);
    }
    return result;
  }
  if (client?.globalHealth) {
    const result = await client.globalHealth();
    if (result?.error) {
      const message = result.error?.message || JSON.stringify(result.error);
      throw new Error(message);
    }
    return result;
  }
  if (client?.health) {
    const result = await client.health();
    if (result?.error) {
      const message = result.error?.message || JSON.stringify(result.error);
      throw new Error(message);
    }
    return result;
  }
  throw new Error("Opencode client does not expose a health method");
};

const disposeClient = async (client: any): Promise<void> => {
  if (client?.instance?.dispose) {
    await client.instance.dispose();
    return;
  }
  if (client?.instanceDispose) {
    await client.instanceDispose();
  }
};

const isUnauthorized = (error: unknown): boolean => {
  if (!error) return false;
  const err = error as { status?: number; statusCode?: number; response?: { status?: number } };
  const status = err.status || err.statusCode || err.response?.status;
  if (status === 401) return true;
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("401");
};

const ensureClient = async (
  baseUrl: string,
  password: string,
  directory?: string,
  serverConfig?: Record<string, unknown>
): Promise<EnsureClientResult> => {
  const authFetch = createAuthFetch(password);
  const authClient = createOpencodeClient({ baseUrl, fetch: authFetch, directory });
  try {
    await callHealth(authClient);
    return { client: authClient, startedServer: null, startedInstance: null };
  } catch (error) {
    if (isUnauthorized(error)) {
      throw new Error(
        "Server is running with a different password. Update the shared password file or stop the existing server."
      );
    }
    const openClient = createOpencodeClient({ baseUrl, directory });
    try {
      await callHealth(openClient);
      throw new Error(
        "Server is running without auth on the configured port. Stop it or configure OPENCODE_SERVER_PASSWORD to match the shared password file."
      );
    } catch (openError) {
      if (openError instanceof Error && openError.message.includes("without auth")) {
        throw openError;
      }
      if (isUnauthorized(openError)) {
        throw new Error(
          "Server requires auth but the shared password did not authenticate. Update the shared password file or stop the existing server."
        );
      }
      const { hostname, port } = resolveServerConfig(baseUrl);
      process.env.OPENCODE_SERVER_PASSWORD = password;
      process.env.OPENCODE_SERVER_USERNAME = SERVER_USERNAME;
      try {
        const opencode = await createOpencode({ hostname, port, config: serverConfig });
        for (let attempt = 0; attempt < SERVER_START_RETRIES; attempt += 1) {
          try {
            await callHealth(authClient);
            return { client: authClient, startedServer: opencode.server, startedInstance: opencode };
          } catch (healthError) {
            if (attempt === SERVER_START_RETRIES - 1) {
              throw healthError;
            }
            await sleep(SERVER_START_DELAY_MS);
          }
        }
        return { client: authClient, startedServer: opencode.server, startedInstance: opencode };
      } catch (startError) {
        const message = startError instanceof Error ? startError.message : String(startError);
        if (message.toLowerCase().includes("address already in use")) {
          await sleep(200);
          await callHealth(authClient);
          return { client: authClient, startedServer: null, startedInstance: null };
        }
        throw startError;
      }
    }
  }
};

export {
  createAuthFetch,
  callHealth,
  disposeClient,
  ensureClient,
  readServerPassword,
  resolveServerConfig,
  SERVER_USERNAME,
};
