type RegistrationInput = {
  organizationId: string;
  email: string;
  password: string;
  displayName: string;
  roleId: string;
  idempotencyKey: string;
};

type RegistrationResult = {
  profile_id: string | null;
  membership_id: string | null;
  assignment_id: string | null;
  result_code: string;
  replayed: boolean;
};

type Dependencies = {
  authenticate(authorization: string): Promise<{ id: string } | null>;
  preflight(
    input: RegistrationInput,
    authorization: string,
  ): Promise<RegistrationResult | null>;
  createAuthUser(email: string, password: string): Promise<string | null>;
  register(
    input: RegistrationInput,
    authUserId: string,
    authorization: string,
  ): Promise<RegistrationResult | null>;
  deleteAuthUser(id: string): Promise<boolean>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reply = (error: string, status: number) =>
  Response.json({ error }, { status });
const success = (result: RegistrationResult, status: number) =>
  Response.json({
    profileId: result.profile_id,
    membershipId: result.membership_id,
    assignmentId: result.assignment_id,
  }, { status });

function parseInput(value: unknown): RegistrationInput | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  const keys = [
    "organizationId",
    "email",
    "password",
    "displayName",
    "roleId",
    "idempotencyKey",
  ];
  if (
    Object.keys(body).length !== keys.length ||
    keys.some((key) => !(key in body))
  ) return null;
  if (
    typeof body.organizationId !== "string" ||
    !uuidPattern.test(body.organizationId) ||
    typeof body.roleId !== "string" || !uuidPattern.test(body.roleId) ||
    typeof body.idempotencyKey !== "string" ||
    !uuidPattern.test(body.idempotencyKey) ||
    typeof body.email !== "string" || body.email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email.trim()) ||
    typeof body.password !== "string" || body.password.length < 12 ||
    body.password.length > 128 ||
    typeof body.displayName !== "string" || !body.displayName.trim() ||
    body.displayName.trim().length > 120
  ) return null;
  return {
    organizationId: body.organizationId,
    email: body.email.trim().toLowerCase(),
    password: body.password,
    displayName: body.displayName.trim(),
    roleId: body.roleId,
    idempotencyKey: body.idempotencyKey,
  };
}

export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply("method_not_allowed", 405);
    const authorization = request.headers.get("Authorization");
    if (!authorization || !/^Bearer\s+\S+$/i.test(authorization)) {
      return reply("unauthorized", 401);
    }
    const caller = await deps.authenticate(authorization).catch(() => null);
    if (!caller) return reply("unauthorized", 401);

    let input: RegistrationInput | null;
    try {
      input = parseInput(await request.json());
    } catch {
      input = null;
    }
    if (!input) return reply("invalid_payload", 400);

    const preflight = await deps.preflight(input, authorization).catch(() =>
      null
    );
    if (!preflight) return reply("registration_failed", 500);
    if (preflight.result_code === "denied") return reply("forbidden", 403);
    if (preflight.result_code === "idempotency_conflict") {
      return reply("idempotency_conflict", 409);
    }
    if (preflight.replayed) {
      return preflight.result_code === "registered"
        ? success(preflight, 200)
        : reply("registration_failed", 409);
    }
    if (preflight.result_code !== "ready") {
      return reply("registration_failed", 409);
    }

    const authUserId = await deps.createAuthUser(input.email, input.password)
      .catch(() => null);
    if (!authUserId) return reply("registration_failed", 400);
    const registered = await deps.register(input, authUserId, authorization)
      .catch(() => null);
    if (registered?.result_code === "registered") {
      return success(registered, 201);
    }
    if (registered?.replayed) {
      const removed = await deps.deleteAuthUser(authUserId).catch(() => false);
      if (!removed) return reply("registration_failed", 500);
      return success(registered, 200);
    }
    const removed = await deps.deleteAuthUser(authUserId).catch(() => false);
    if (!removed) return reply("registration_failed", 500);
    if (registered?.result_code === "idempotency_conflict") {
      return reply("idempotency_conflict", 409);
    }
    if (registered?.result_code === "denied") return reply("forbidden", 403);
    return reply("registration_failed", 409);
  };
}

export type { Dependencies, RegistrationInput, RegistrationResult };
