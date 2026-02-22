import fs from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { expect, test } from "vitest";
import { createOpencode, createOpencodeClient } from "@opencode-ai/sdk/v2";

const shouldRun = process.env.OPENCODE_INTEGRATION === "1";

const pickPort = async () => {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  server.close();
  return typeof address === "object" && address ? address.port : 0;
};

test.skipIf(!shouldRun)("applies edits with server permissions", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "opencode-test-"));
  const targetPath = path.join(tempDir, "sample.lua");
  await fs.writeFile(targetPath, "local x = 1\n", "utf8");

  const serverConfig = {
    formatter: false,
    lsp: false,
    snapshot: false,
    agent: {
      build: {
        steps: 20,
        temperature: 0,
        prompt: [
          "You must use the edit tool to apply requested changes.",
          "Do not reply before the edit is complete.",
          "After editing, respond with DONE only.",
        ].join("\n"),
      },
      title: { disable: true },
      summary: { disable: true },
      compaction: { disable: true },
    },
  };

  const port = await pickPort();
  const opencode = await createOpencode({ hostname: "127.0.0.1", port, config: serverConfig });

  try {
    const client = createOpencodeClient({ baseUrl: opencode.server.url, directory: tempDir });
    const sessionResult = await client.session.create({
      directory: tempDir,
      title: "Opencode Test",
    });
    const session = sessionResult?.data ?? sessionResult;
    const sessionId =
      session?.id ||
      session?.sessionId ||
      session?.sessionID ||
      session?.session_id ||
      session?.info?.id ||
      session?.info?.sessionId ||
      session?.info?.sessionID ||
      session?.info?.session_id;

    expect(sessionId).toBeTruthy();

    const promptText = [
      "Comment out the first line in this file:",
      targetPath,
      "Use the edit tool.",
      "Reply with DONE only after the file is updated.",
    ].join("\n");

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);
    let response;
    try {
      response = await client.session.prompt({
        sessionID: sessionId,
        directory: tempDir,
        parts: [{ type: "text", text: promptText }],
        model: { providerID: "openai", modelID: "gpt-5.1-codex-mini" },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }

    if (response?.error) {
      throw new Error(response.error?.message || JSON.stringify(response.error));
    }

    const responseData = response?.data ?? response;
    const parts = Array.isArray(responseData?.parts) ? responseData.parts : [];
    const text = parts
      .filter((part) => part?.type === "text")
      .map((part) => part.text)
      .join("\n");

    expect(text).toMatch(/DONE/i);

    const updated = await fs.readFile(targetPath, "utf8");
    expect(updated.split("\n")[0]).toBe("-- local x = 1");
  } finally {
    opencode.server.close();
  }
}, 40000);
