import { createHandler } from "./handler.ts";
import type {
  Dependencies,
  RegistrationInput,
  RegistrationResult,
} from "./handler.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed: ${JSON.stringify(actual)} !== ${
        JSON.stringify(expected)
      }`,
    );
  }
}
function assertStringIncludes(actual: string, expected: string) {
  if (!actual.includes(expected)) {
    throw new Error(`Assertion failed: missing ${expected}`);
  }
}

const input: RegistrationInput = {
  organizationId: "11111111-1111-4111-8111-111111111111",
  email: "new@example.test",
  password: "synthetic-password-123",
  displayName: "Synthetic user",
  roleId: "22222222-2222-4222-8222-222222222222",
  idempotencyKey: "33333333-3333-4333-8333-333333333333",
};
const result: RegistrationResult = {
  profile_id: "44444444-4444-4444-8444-444444444444",
  membership_id: "55555555-5555-4555-8555-555555555555",
  assignment_id: "66666666-6666-4666-8666-666666666666",
  result_code: "registered",
  replayed: false,
};
const request = (body: unknown = input, headers = true, method = "POST") =>
  new Request("https://local.test", {
    method,
    headers: headers
      ? {
        Authorization: "Bearer synthetic-jwt",
        "Content-Type": "application/json",
      }
      : {},
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
function setup(overrides: Partial<Dependencies> = {}) {
  const calls = { auth: 0, preflight: 0, create: 0, register: 0, delete: 0 };
  const deps: Dependencies = {
    authenticate: async () => {
      await Promise.resolve();
      calls.auth++;
      return { id: "actor" };
    },
    preflight: async () => {
      await Promise.resolve();
      calls.preflight++;
      return {
        ...result,
        result_code: "ready",
        replayed: false,
        profile_id: null,
        membership_id: null,
        assignment_id: null,
      };
    },
    createAuthUser: async () => {
      await Promise.resolve();
      calls.create++;
      return "new-auth-id";
    },
    register: async () => {
      await Promise.resolve();
      calls.register++;
      return result;
    },
    deleteAuthUser: async () => {
      await Promise.resolve();
      calls.delete++;
      return true;
    },
    ...overrides,
  };
  return { handler: createHandler(deps), calls };
}

Deno.test("rejects non-POST methods", async () => {
  const { handler } = setup();
  assertEquals((await handler(request(input, true, "GET"))).status, 405);
});
Deno.test("rejects missing or invalid caller token", async () => {
  const missing = setup();
  assertEquals((await missing.handler(request(input, false))).status, 401);
  const invalid = setup({
    authenticate: async () => {
      await Promise.resolve();
      return null;
    },
  });
  assertEquals((await invalid.handler(request())).status, 401);
});
Deno.test("rejects payload with extra keys or invalid values", async () => {
  const { handler } = setup();
  assertEquals(
    (await handler(request({ ...input, role: "administrator" }))).status,
    400,
  );
  assertEquals(
    (await handler(request({ ...input, password: "short" }))).status,
    400,
  );
});
Deno.test("returns forbidden from caller-scoped preflight", async () => {
  const { handler } = setup({
    preflight: async () => {
      await Promise.resolve();
      return { ...result, result_code: "denied" };
    },
  });
  assertEquals((await handler(request())).status, 403);
});
Deno.test("returns prior result before creating an Auth user", async () => {
  const { handler, calls } = setup({
    preflight: async () => {
      await Promise.resolve();
      return { ...result, replayed: true };
    },
  });
  const response = await handler(request());
  assertEquals(response.status, 200);
  assertEquals(calls.create, 0);
});
Deno.test("returns idempotency conflict", async () => {
  const { handler } = setup({
    preflight: async () => {
      await Promise.resolve();
      return { ...result, result_code: "idempotency_conflict" };
    },
  });
  assertEquals((await handler(request())).status, 409);
});
Deno.test("creates and registers successfully", async () => {
  const { handler, calls } = setup();
  const response = await handler(request());
  assertEquals(response.status, 201);
  assertEquals(calls.register, 1);
  assertEquals(await response.json(), {
    profileId: result.profile_id,
    membershipId: result.membership_id,
    assignmentId: result.assignment_id,
  });
});
Deno.test("normalizes email before Auth creation and registration", async () => {
  let createdEmail = "";
  let registeredEmail = "";
  const { handler } = setup({
    createAuthUser: async (email) => {
      await Promise.resolve();
      createdEmail = email;
      return "new-auth-id";
    },
    register: async (value) => {
      await Promise.resolve();
      registeredEmail = value.email;
      return result;
    },
  });
  const response = await handler(
    request({ ...input, email: "  MEMBER@Example.Test  " }),
  );
  assertEquals(response.status, 201);
  assertEquals(createdEmail, "member@example.test");
  assertEquals(registeredEmail, "member@example.test");
});
Deno.test("fails neutrally when Auth creation fails", async () => {
  const { handler, calls } = setup({
    createAuthUser: async () => {
      await Promise.resolve();
      return null;
    },
  });
  const response = await handler(request());
  assertEquals(response.status, 400);
  assertEquals(calls.register, 0);
});
Deno.test("cleans up after authority is revoked between preflight and registration", async () => {
  const { handler, calls } = setup({
    register: async () => {
      await Promise.resolve();
      return { ...result, result_code: "denied" };
    },
  });
  assertEquals((await handler(request())).status, 403);
  assertEquals(calls.create, 1);
  assertEquals(calls.delete, 1);
});
Deno.test("returns neutral server error if revoked-authority cleanup fails", async () => {
  const { handler } = setup({
    register: async () => {
      await Promise.resolve();
      return { ...result, result_code: "denied" };
    },
    deleteAuthUser: async () => {
      await Promise.resolve();
      return false;
    },
  });
  const response = await handler(request());
  assertEquals(response.status, 500);
  assertEquals(await response.text(), '{"error":"registration_failed"}');
});
Deno.test("compensates Auth user after database failure", async () => {
  const { handler, calls } = setup({
    register: async () => {
      await Promise.resolve();
      return null;
    },
  });
  assertEquals((await handler(request())).status, 409);
  assertEquals(calls.delete, 1);
});
Deno.test("ambiguous post-commit failure can replay without another Auth user", async () => {
  let preflightCalls = 0;
  let createCalls = 0;
  const { handler } = setup({
    preflight: async () => {
      await Promise.resolve();
      preflightCalls++;
      return preflightCalls === 1
        ? {
          ...result,
          result_code: "ready",
          replayed: false,
          profile_id: null,
          membership_id: null,
          assignment_id: null,
        }
        : { ...result, result_code: "registered", replayed: true };
    },
    createAuthUser: async () => {
      await Promise.resolve();
      createCalls++;
      return `new-auth-id-${createCalls}`;
    },
    register: async () => {
      await Promise.resolve();
      return null;
    },
    deleteAuthUser: async () => {
      await Promise.resolve();
      return false;
    },
  });
  assertEquals((await handler(request())).status, 500);
  const replay = await handler(request());
  assertEquals(replay.status, 200);
  assertEquals(createCalls, 1);
});
Deno.test("reports rollback failure without returning secrets", async () => {
  const { handler } = setup({
    register: async () => {
      await Promise.resolve();
      return null;
    },
    deleteAuthUser: async () => {
      await Promise.resolve();
      return false;
    },
  });
  const response = await handler(request());
  const body = await response.text();
  assertEquals(response.status, 500);
  assertStringIncludes(body, "registration_failed");
  assertEquals(body.includes(input.email), false);
  assertEquals(body.includes(input.password), false);
});
