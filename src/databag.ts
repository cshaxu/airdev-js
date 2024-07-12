import crypto from "crypto";

function decrypt(text: string, password: string) {
  const textParts = text.split(":");
  const firstPart = textParts.shift();
  if (!firstPart) {
    throw new Error("Invalid encrypted text");
  }
  const iv = Buffer.from(firstPart, "hex");
  const encryptedText = Buffer.from(textParts.join(":"), "hex");
  const decipher = crypto.createDecipheriv(
    "aes-256-cbc",
    Buffer.from(password, "hex"),
    iv
  );
  let decrypted = decipher.update(encryptedText);
  decrypted = Buffer.concat([decrypted, decipher.final()]);
  return decrypted.toString();
}

type Config = { [key: string]: string | Config };

export function decryptConfig<T extends Config>(
  config: T,
  password: string
): T {
  return Object.entries(config).reduce((acc, [key, value]) => {
    (acc as any)[key] =
      typeof value === "string"
        ? decrypt(value, password)
        : decryptConfig(value, password);
    return acc;
  }, {} as T);
}
