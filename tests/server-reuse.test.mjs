import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { beforeAll, beforeEach, expect, test, vi } from "vitest";

/** @type {import("vitest").Mock} */
const createOpencodeClient = vi.fn();
/** @type {import("vitest").Mock} */
const createOpencode = vi.fn();

vi.mock("@opencode-ai/sdk/v2", () => ({
  createOpencodeClient,
  createOpencode,
}));

/** @type {any} */
let callHealth;
/** @type {any} */
let disposeClient;
/** @type {any} */
let ensureClient;
/** @type {any} */
let readServerPassword;

beforeAll(async () => {
  ({
    callHealth,
    disposeClient,
    ensureClient,
    readServerPassword,
  } = await import("../scripts/opencode-server.ts"));
});

beforeEach(() => {
  createOpencodeClient.mockReset();
  createOpencode.mockReset();
});

const makeTempDir = async () => fs.mkdtemp(path.join(os.tmpdir(), "opencode-"));

test("ensureClient starts server when missing", async () => {
  const tempDir = await makeTempDir();
  const passwordFile = path.join(tempDir, "server.json");
  const password = await readServerPassword(passwordFile);
  const baseUrl = "http://127.0.0.1:4000";

  const authClient = {
    global: {
      health: vi.fn()
        .mockRejectedValueOnce(new Error("down"))
        .mockResolvedValue({ data: { healthy: true } }),
    },
  };
  const openClient = { global: { health: vi.fn().mockRejectedValue(new Error("down")) } };
  const server = { close: vi.fn() };

  createOpencodeClient.mockImplementation((config) => (config?.fetch ? authClient : openClient));
  createOpencode.mockResolvedValue({ server, client: {} });

  const { client, startedServer } = await ensureClient(baseUrl, password);
  expect(startedServer).toBe(server);
  expect(createOpencode).toHaveBeenCalledOnce();

  await disposeClient(client);
});

test("ensureClient errors if server is running without auth", async () => {
  const tempDir = await makeTempDir();
  const passwordFile = path.join(tempDir, "server.json");
  const password = await readServerPassword(passwordFile);
  const baseUrl = "http://127.0.0.1:4002";

  const authClient = { global: { health: vi.fn().mockRejectedValue(new Error("down")) } };
  const openClient = { global: { health: vi.fn().mockResolvedValue({ data: { healthy: true } }) } };

  createOpencodeClient.mockImplementation((config) => (config?.fetch ? authClient : openClient));

  await expect(ensureClient(baseUrl, password)).rejects.toThrow(
    "Server is running without auth"
  );
  expect(createOpencode).not.toHaveBeenCalled();
});

test("ensureClient errors on wrong password", async () => {
  const tempDir = await makeTempDir();
  const passwordFile = path.join(tempDir, "server.json");
  const password = await readServerPassword(passwordFile);
  const baseUrl = "http://127.0.0.1:4003";

  const authError = { status: 401, message: "Unauthorized" };
  const authClient = { global: { health: vi.fn().mockRejectedValue(authError) } };

  createOpencodeClient.mockImplementation(() => authClient);

  await expect(ensureClient(baseUrl, password)).rejects.toThrow(
    "different password"
  );
  expect(createOpencode).not.toHaveBeenCalled();
});

test("ensureClient reuses existing server", async () => {
  const tempDir = await makeTempDir();
  const passwordFile = path.join(tempDir, "server.json");
  const password = await readServerPassword(passwordFile);
  const baseUrl = "http://127.0.0.1:4001";

  const authClient = { global: { health: vi.fn().mockResolvedValue({ data: { healthy: true } }) } };
  const openClient = { global: { health: vi.fn() } };

  createOpencodeClient.mockImplementation((config) => (config?.fetch ? authClient : openClient));

  const { client, startedServer } = await ensureClient(baseUrl, password);
  expect(startedServer).toBeNull();
  expect(await callHealth(client)).toEqual({ data: { healthy: true } });
  expect(createOpencode).not.toHaveBeenCalled();

  await disposeClient(client);
});

test("ensureClient retries when port becomes available", async () => {
  const tempDir = await makeTempDir();
  const passwordFile = path.join(tempDir, "server.json");
  const password = await readServerPassword(passwordFile);
  const baseUrl = "http://127.0.0.1:4004";

  const authClient = { global: { health: vi.fn() } };
  const openClient = { global: { health: vi.fn().mockRejectedValue(new Error("down")) } };

  authClient.global.health
    .mockRejectedValueOnce(new Error("down"))
    .mockResolvedValue({ data: { healthy: true } });

  createOpencodeClient.mockImplementation((config) => (config?.fetch ? authClient : openClient));
  createOpencode.mockRejectedValue(new Error("Address already in use"));

  const { client, startedServer } = await ensureClient(baseUrl, password);
  expect(startedServer).toBeNull();
  expect(await callHealth(client)).toEqual({ data: { healthy: true } });
});
