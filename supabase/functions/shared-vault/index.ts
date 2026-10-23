import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const maxFileSize = 4 * 1024 * 1024;
const bucket = "shared-vault";
const settingsId = 1;

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const sha256 = async (value: string) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");

const constantTimeEqual = async (left: string, right: string) => {
  const leftHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(left)),
  );
  const rightHash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(right)),
  );
  let difference = 0;
  for (let index = 0; index < leftHash.length; index++) {
    difference |= leftHash[index] ^ rightHash[index];
  }
  return difference === 0;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !serviceKey) {
    return json(503, { error: "Shared folder has not been configured by its owner." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Invalid request." });
  }
  const action = body.action;
  const pin = typeof body.pin === "string" ? body.pin : "";
  const clientIp = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const ipBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(clientIp));
  const ipHash = Array.from(new Uint8Array(ipBytes), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const admin = createClient(projectUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const adminResetKey = Deno.env.get("SHARED_FOLDER_ADMIN_KEY");
  if (action === "admin-verify" || action === "admin-set-pin") {
    if (!adminResetKey) {
      return json(503, { error: "Admin password reset has not been configured." });
    }
    const suppliedKey = typeof body.adminKey === "string" ? body.adminKey : "";
    if (!await constantTimeEqual(suppliedKey, adminResetKey)) {
      const { data: allowed, error } = await admin.rpc("record_shared_pin_failure", {
        p_ip_hash: ipHash,
      });
      if (error) {
        console.error("Unable to apply admin reset rate limit.", error.message);
        return json(500, { error: "Unable to verify admin access." });
      }
      return json(allowed ? 401 : 429, {
        error: allowed
          ? "The admin reset key is incorrect."
          : "Too many failed attempts. Try again in 15 minutes.",
      });
    }
    if (action === "admin-verify") {
      return json(200, { authorized: true });
    }
    const newPin = typeof body.newPin === "string" ? body.newPin : "";
    if (!/^\d{4}$/.test(newPin)) {
      return json(400, { error: "The new shared-folder password must be 4 digits." });
    }
    const pinSalt = crypto.randomUUID();
    const pinHash = await sha256(`${pinSalt}:${newPin}`);
    const { error } = await admin.from("shared_folder_settings").upsert({
      id: settingsId,
      pin_salt: pinSalt,
      pin_hash: pinHash,
    });
    if (error) {
      console.error("Unable to reset shared-folder password.", error.message);
      return json(500, { error: "Unable to reset the shared-folder password." });
    }
    return json(200, { updated: true });
  }

  const { data: pinSettings, error: settingsError } = await admin
    .from("shared_folder_settings")
    .select("pin_salt,pin_hash")
    .eq("id", settingsId)
    .maybeSingle();
  if (settingsError) {
    console.error("Unable to read shared-folder settings.", settingsError.message);
    return json(500, { error: "Unable to read shared-folder settings." });
  }
  const configuredPin = Deno.env.get("SHARED_FOLDER_PIN");
  if (!pinSettings && (!configuredPin || !/^\d{4}$/.test(configuredPin))) {
    return json(503, {
      error: "The shared-folder password has not been set by an admin.",
    });
  }
  const pinConfigured = pinSettings
    ? await constantTimeEqual(
      await sha256(`${pinSettings.pin_salt}:${pin}`),
      pinSettings.pin_hash,
    )
    : Boolean(configuredPin && /^\d{4}$/.test(configuredPin) && pin === configuredPin);
  if (!/^\d{4}$/.test(pin) || !pinConfigured) {
    const { data: allowed, error } = await admin.rpc("record_shared_pin_failure", {
      p_ip_hash: ipHash,
    });
    if (error) {
      console.error("Unable to apply shared PIN rate limit.", error.message);
      return json(500, { error: "Unable to validate the shared password." });
    }
    return json(allowed ? 401 : 429, {
      error: allowed
        ? "Incorrect shared-folder password."
        : "Too many incorrect attempts. Try again in 15 minutes.",
    });
  }
  await admin.rpc("clear_shared_pin_failures", { p_ip_hash: ipHash });

  try {
    if (action === "list" || action === "list-trash") {
      let query = admin
        .from("shared_files")
        .select("id,name,content_type,size,created_at")
        .order(action === "list" ? "created_at" : "deleted_at", {
          ascending: false,
        });
      query = action === "list"
        ? query.is("deleted_at", null)
        : query.not("deleted_at", "is", null);
      const { data, error } = await query.limit(500);
      if (error) throw error;
      return json(200, {
        files: data.map((file) => ({
          id: file.id,
          name: file.name,
          contentType: file.content_type,
          size: file.size,
          createdAt: file.created_at,
        })),
      });
    }

    if (action === "trash" || action === "restore") {
      const id = typeof body.id === "string" ? body.id : "";
      if (!/^[0-9a-f-]{36}$/i.test(id)) {
        return json(400, { error: "Invalid file ID." });
      }
      const update = action === "trash"
        ? admin
          .from("shared_files")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", id)
          .is("deleted_at", null)
        : admin
          .from("shared_files")
          .update({ deleted_at: null })
          .eq("id", id)
          .not("deleted_at", "is", null);
      const { data, error } = await update.select("id").maybeSingle();
      if (error) throw error;
      if (!data) {
        return json(404, {
          error: action === "trash"
            ? "Shared file not found."
            : "File was not found in the shared-folder trash.",
        });
      }
      return json(200, { id, restored: action === "restore" });
    }

    if (action === "upload") {
      const name = typeof body.name === "string" ? body.name.trim() : "";
      const content = typeof body.contentBase64 === "string" ? body.contentBase64 : "";
      if (!name || name.length > 255 || name.includes("/") || name.includes("\\")) {
        return json(400, { error: "Invalid file name." });
      }
      if (content.length > Math.ceil(maxFileSize * 4 / 3) + 8) {
        return json(413, { error: "Shared uploads are limited to 4 MB." });
      }
      const bytes = Uint8Array.from(atob(content), (character) => character.charCodeAt(0));
      if (bytes.length > maxFileSize) {
        return json(413, { error: "Shared uploads are limited to 4 MB." });
      }
      const id = crypto.randomUUID();
      const path = `${id}`;
      const { error: uploadError } = await admin.storage.from(bucket).upload(
        path,
        bytes,
        { contentType: "application/octet-stream", upsert: false },
      );
      if (uploadError) throw uploadError;
      const { error: insertError } = await admin.from("shared_files").insert({
        id,
        name,
        storage_path: path,
        size: bytes.length,
        content_type: "application/octet-stream",
      });
      if (insertError) {
        await admin.storage.from(bucket).remove([path]);
        throw insertError;
      }
      return json(200, { id });
    }

    if (action === "download") {
      const id = typeof body.id === "string" ? body.id : "";
      if (!/^[0-9a-f-]{36}$/i.test(id)) return json(400, { error: "Invalid file ID." });
      const { data: row, error: rowError } = await admin
        .from("shared_files")
        .select("storage_path")
        .eq("id", id)
        .maybeSingle();
      if (rowError) throw rowError;
      if (!row) return json(404, { error: "Shared file not found." });
      const { data, error } = await admin.storage.from(bucket).download(row.storage_path);
      if (error) throw error;
      if (data.size > maxFileSize) return json(413, { error: "File exceeds the download limit." });
      const bytes = new Uint8Array(await data.arrayBuffer());
      let binary = "";
      for (let offset = 0; offset < bytes.length; offset += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
      }
      const encoded = btoa(binary);
      return json(200, { contentBase64: encoded });
    }

    return json(400, { error: "Unsupported shared-folder action." });
  } catch (error) {
    console.error("Shared folder request failed.", error);
    return json(500, { error: "The shared-folder request failed." });
  }
});
