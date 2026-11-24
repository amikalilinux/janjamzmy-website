import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Sign-in required' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? '';
  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !publishableKey || !secretKey) return json({ error: 'Server environment is not configured' }, 500);

  const token = authHeader.slice('Bearer '.length);
  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const adminClient = createClient(supabaseUrl, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: 'Invalid session' }, 401);

  const { data: actor, error: actorError } = await adminClient
    .from('profiles')
    .select('role,is_active')
    .eq('id', userData.user.id)
    .single();
  if (actorError || actor?.role !== 'owner' || actor?.is_active !== true) {
    return json({ error: 'Only an active owner can invite team members' }, 403);
  }

  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  const email = String(input.email ?? '').trim().toLowerCase();
  const fullName = String(input.full_name ?? '').trim().slice(0, 100);
  const jobTitle = String(input.job_title ?? '').trim().slice(0, 120);
  const role = String(input.role ?? 'member');

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'Enter a valid email address' }, 400);
  if (!fullName) return json({ error: 'Full name is required' }, 400);
  if (!['member', 'manager'].includes(role)) return json({ error: 'Role must be member or manager' }, 400);

  const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName },
  });
  if (inviteError || !invited.user) return json({ error: inviteError?.message ?? 'Invitation failed' }, 400);

  // The Auth trigger creates the profile as a regular member; this trusted server-side
  // update can then promote only to manager when the active owner explicitly requested it.
  const { error: profileError } = await adminClient
    .from('profiles')
    .update({ full_name: fullName, job_title: jobTitle || null, role })
    .eq('id', invited.user.id);
  if (profileError) return json({ error: `User was invited but profile setup failed: ${profileError.message}` }, 500);

  return json({ success: true, user_id: invited.user.id, email });
});
