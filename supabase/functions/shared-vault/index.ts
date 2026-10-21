import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const maxFileSize = 4 * 1024 * 1024;
const bucket = "shared-vault";

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });

  const configuredPin = Deno.env.get("SHARED_FOLDER_PIN");
  const projectUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!configuredPin || !/^\d{4}$/.test(configuredPin) || !projectUrl || !serviceKey) {
    return json(503, { error: "Shared folder has not been configured by its owner." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Invalid request." });
  }
  const pin = typeof body.pin === "string" ? body.pin : "";
  const action = body.action;
  const clientIp = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const ipBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(clientIp));
  const ipHash = Array.from(new Uint8Array(ipBytes), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const admin = createClient(projectUrl, serviceKey, {
    auth: { persistSession: false },
  });

  if (!/^\d{4}$/.test(pin) || pin !== configuredPin) {
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
    if (action === "list") {
      const { data, error } = await admin
        .from("shared_files")
        .select("id,name,content_type,size,created_at")
        .order("created_at", { ascending: false })
        .limit(500);
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
