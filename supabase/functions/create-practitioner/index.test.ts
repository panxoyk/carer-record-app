const baseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
const requestSignal = () => AbortSignal.timeout(10000);

if (!baseUrl || !publishableKey) {
  throw new Error("SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required");
}

function expect(condition: unknown, message: string): void {
  if (!condition) throw new Error(message);
}

const parseJson = async (
  response: Response,
): Promise<Record<string, unknown>> => {
  const value: unknown = await response.json();
  expect(
    value && typeof value === "object" && !Array.isArray(value),
    "Expected JSON object",
  );
  return value as Record<string, unknown>;
};

const signIn = async (email: string, password: string) => {
  const response = await fetch(
    `${baseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
      signal: requestSignal(),
    },
  );
  expect(response.ok, `Expected ${email} to sign in`);
  const body = await parseJson(response);
  const accessToken = body.access_token;
  if (typeof accessToken !== "string") {
    throw new Error("Expected access token");
  }
  return accessToken;
};

const invokeCreate = (token: string | null, body: unknown, method = "POST") =>
  fetch(`${baseUrl}/functions/v1/create-practitioner`, {
    method,
    headers: {
      apikey: publishableKey,
      "Content-Type": "application/json",
      ...(token != null ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
    signal: requestSignal(),
  });

Deno.test("create-practitioner rejects unauthenticated and unauthorized callers", async () => {
  const unauthenticated = await invokeCreate(null, {});
  expect(
    unauthenticated.status === 401,
    "Expected unauthenticated request to fail",
  );

  const physicianToken = await signIn(
    "ana.torres@example.test",
    "ChangeMe123!",
  );
  const forbidden = await invokeCreate(physicianToken, {});
  expect(forbidden.status === 403, "Expected physician request to fail");

  const suspendedToken = await signIn(
    "camila.vera@example.test",
    "ChangeMe123!",
  );
  const suspended = await invokeCreate(suspendedToken, {});
  expect(suspended.status === 403, "Expected suspended administrator to fail");
});

Deno.test("create-practitioner validates input and creates an active profile", async () => {
  const administratorToken = await signIn("admin@example.test", "ChangeMe123!");
  const invalid = await invokeCreate(administratorToken, { role: "unknown" });
  expect(invalid.status === 400, "Expected invalid payload to fail");
  expect(
    (await parseJson(invalid)).error === "invalid_payload",
    "Expected stable error",
  );

  const duplicate = await invokeCreate(administratorToken, {
    email: "ana.torres@example.test",
    password: "TestPassword123!",
    displayName: "Duplicate Test",
    role: "nurse",
  });
  expect(duplicate.status === 400, "Expected duplicate email to fail");
  expect(
    (await parseJson(duplicate)).error === "creation_failed",
    "Expected stable duplicate error",
  );

  const email = `function-test-${crypto.randomUUID()}@example.test`;
  const created = await invokeCreate(administratorToken, {
    email,
    password: "TestPassword123!",
    displayName: "Function Test",
    role: "nurse",
  });
  expect(created.status === 201, "Expected practitioner creation to succeed");
  const createdBody = await parseJson(created);
  expect(typeof createdBody.id === "string", "Expected practitioner id");

  const practitionerToken = await signIn(email, "TestPassword123!");
  const profile = await fetch(
    `${baseUrl}/rest/v1/practitioners?select=role,status&id=eq.${createdBody.id}`,
    {
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${practitionerToken}`,
      },
      signal: requestSignal(),
    },
  );
  expect(profile.ok, "Expected new practitioner profile to be readable");
  const profiles: unknown = await profile.json();
  expect(
    Array.isArray(profiles) && profiles.length === 1,
    "Expected one profile",
  );
  const practitioner = (profiles as Record<string, unknown>[])[0];
  expect(practitioner.role === "nurse", "Expected persisted role");
  expect(practitioner.status === "active", "Expected active practitioner");
});

Deno.test("create-practitioner compensates when profile creation fails", async () => {
  const administratorToken = await signIn("admin@example.test", "ChangeMe123!");
  const email = `rollback-test-${crypto.randomUUID()}@example.test`;
  const created = await invokeCreate(administratorToken, {
    email,
    password: "TestPassword123!",
    displayName: "Rollback Test",
    role: "physician",
    licenseNumber: "MED-10001",
  });
  expect(created.status === 500, "Expected profile creation failure");
  expect(
    (await parseJson(created)).error === "creation_failed",
    "Expected stable error",
  );

  const login = await fetch(`${baseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: publishableKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: "TestPassword123!" }),
    signal: requestSignal(),
  });
  expect(login.status === 400, "Expected compensated Auth user to be absent");
});
