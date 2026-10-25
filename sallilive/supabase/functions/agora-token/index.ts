// Supabase Edge Function: issues a short-lived Agora RTC token for a live room.
// Secrets required: AGORA_APP_ID, AGORA_APP_CERTIFICATE
import { createClient } from "npm:@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const { room_id } = await req.json();
    const { data: profile } = await sb.from("profiles").select("display_id,is_banned").eq("id", user.id).single();
    if (!profile || profile.is_banned) return json({ error: "banned" }, 403);

    const { data: room } = await sb.from("rooms").select("id,is_live").eq("id", room_id).maybeSingle();
    if (!room || !room.is_live) return json({ error: "room_closed" }, 404);

    const appId = Deno.env.get("AGORA_APP_ID")!;
    const cert = Deno.env.get("AGORA_APP_CERTIFICATE")!;
    const uid = Number(profile.display_id);
    const ttl = 6 * 3600; // seconds from now
    const token = RtcTokenBuilder.buildTokenWithUid(appId, cert, room_id, uid, RtcRole.PUBLISHER, ttl, ttl);
    return json({ token, uid, app_id: appId });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
