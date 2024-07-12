#!/usr/bin/env node

const nodeCrypto = require("crypto");
const fs = require("fs");
const path = require("path");

const PROJECT_PATH = process.cwd();

function encrypt(text, password) {
  const iv = nodeCrypto.randomBytes(16); // generate a random iv
  const cipher = nodeCrypto.createCipheriv(
    "aes-256-cbc",
    Buffer.from(password, "hex"),
    iv
  );
  let encrypted = cipher.update(text);
  encrypted = Buffer.concat([encrypted, cipher.final()]);
  return iv.toString("hex") + ":" + encrypted.toString("hex");
}

function decrypt(text, password) {
  const textParts = text.split(":");
  const iv = Buffer.from(textParts.shift(), "hex");
  const encryptedText = Buffer.from(textParts.join(":"), "hex");
  const decipher = nodeCrypto.createDecipheriv(
    "aes-256-cbc",
    Buffer.from(password, "hex"),
    iv
  );
  let decrypted = decipher.update(encryptedText);
  decrypted = Buffer.concat([decrypted, decipher.final()]);
  return decrypted.toString();
}

function processJson(json, password, isEncrypt) {
  return Object.entries(json).reduce((acc, [key, value]) => {
    if (typeof value === "string") {
      try {
        acc[key] = isEncrypt
          ? encrypt(value, password)
          : decrypt(value, password);
      } catch {
        acc[key] = value;
      }
    } else {
      acc[key] = processJson(value, password, isEncrypt);
    }
    return acc;
  }, {});
}

// Usage

async function main(args) {
  const jsonFile = args
    .filter((arg) => arg.startsWith("--file="))
    .map((arg) => arg.replace("--file=", ""))
    .at(0);
  if (!jsonFile?.length) {
    throw new Error('[AIRDEV-DATABAG/ERROR] missing "--file" argument');
  }

  const jsonFilePath = path.join(PROJECT_PATH, jsonFile);
  if (!fs.existsSync(jsonFilePath)) {
    throw new Error(`[AIRDEV-DATABAG/ERROR] missing "${jsonFilePath}"`);
  }

  const password = args
    .filter((arg) => arg.startsWith("--password="))
    .map((arg) => arg.replace("--password=", ""))
    .at(0);
  if (!password?.length) {
    throw new Error('[AIRDEV-DATABAG/ERROR] missing "--password" argument');
  }

  const json = await fs.promises
    .readFile(jsonFilePath, "utf8")
    .then(JSON.parse);

  const isEncrypt = args.includes("--encrypt");
  const isDecrypt = args.includes("--decrypt");
  const output = args
    .filter((arg) => arg.startsWith("--output="))
    .map((arg) => arg.replace("--output=", ""))
    .at(0);
  const outputPath = output?.length
    ? path.join(PROJECT_PATH, output)
    : jsonFilePath;
  if (isEncrypt || isDecrypt) {
    const processedJson = processJson(json, password, isEncrypt);
    await fs.promises.writeFile(
      outputPath,
      JSON.stringify(processedJson, null, 2)
    );
    console.log(
      `[AIRDEV-DATABAG] successfully ${isEncrypt ? "encrypted" : "decrypted"}`
    );
    return;
  }

  const keyPath = args
    .filter((arg) => arg.startsWith("--key="))
    .map((arg) => arg.replace("--key=", ""))
    .at(0);
  if (!keyPath?.length) {
    throw new Error('[AIRDEV-DATABAG/ERROR] missing "--key" argument');
  }
  const keyPathParts = keyPath.split(/[./]/);

  const value = args
    .filter((arg) => arg.startsWith("--value="))
    .map((arg) => arg.replace("--value=", ""))
    .at(0);
  if (value?.length) {
    let entry = json;

    for (let i = 0; i < keyPathParts.length - 1; i++) {
      const keyPathPart = keyPathParts[i];
      entry[keyPathPart] = entry[keyPathPart] ?? {};
      entry = entry[keyPathPart];
    }

    entry[keyPathParts.at(-1)] = encrypt(value, password);
    await fs.promises.writeFile(outputPath, JSON.stringify(json, null, 2));

    console.log(
      `[AIRDEV-DATABAG] "${keyPath}" updated to "${decrypt(
        entry[keyPathParts.at(-1)],
        password
      )}"`
    );
  } else {
    let entry = json;
    for (const keyPathPart of keyPathParts) {
      entry = entry[keyPathPart];
      if (!entry) {
        throw new Error(`[AIRDEV-DATABAG/ERROR] missing "${keyPathPart}"`);
      }
    }

    console.log(decrypt(entry, password));
  }
}

main(process.argv.slice(2)).catch(console.error);
