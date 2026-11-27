// Test helpers: a fake Supabase client and a dependency bundle with canned AI answers.
import type { Ctx, Deps } from "./deps.ts";

export interface Call {
  op: string;
  table?: string;
  name?: string;
  payload?: unknown;
}

export interface FakeOpts {
  rpc?: Record<string, unknown>; // rpc name -> data returned
  single?: Record<string, unknown>; // table -> row for single()/maybeSingle()
  rows?: Record<string, unknown[]>; // table -> rows for list queries
  counts?: Record<string, number>; // table -> count for count queries
  downloadError?: boolean;
}

export function fakeSupabase(opts: FakeOpts = {}) {
  const calls: Call[] = [];
  const query = (table: string) => {
    // deno-lint-ignore no-explicit-any
    const q: any = {};
    for (const m of ["select", "eq", "not", "gte", "order", "limit"]) q[m] = () => q;
    q.insert = (payload: unknown) => {
      calls.push({ op: "insert", table, payload });
      return q;
    };
    q.update = (payload: unknown) => {
      calls.push({ op: "update", table, payload });
      return q;
    };
    q.maybeSingle = async () => ({ data: opts.single?.[table] ?? null, error: null });
    q.single = async () => ({ data: opts.single?.[table] ?? { id: "new-id" }, error: null });
    // deno-lint-ignore no-explicit-any
    q.then = (res: any, rej: any) =>
      Promise.resolve({ data: opts.rows?.[table] ?? [], count: opts.counts?.[table] ?? 0, error: null }).then(res, rej);
    return q;
  };
  const client = {
    from: query,
    rpc: async (name: string, args?: unknown) => {
      calls.push({ op: "rpc", name, payload: args });
      return { data: opts.rpc?.[name] ?? null, error: null };
    },
    storage: {
      from: () => ({
        download: async () =>
          opts.downloadError ? { data: null, error: { message: "not found" } } : { data: new Blob(["audio"]), error: null },
        remove: async (paths: string[]) => {
          calls.push({ op: "remove", payload: paths });
          return { error: null };
        },
      }),
    },
  };
  return { client, calls };
}

export interface HarnessOpts {
  sb?: FakeOpts;
  authed?: boolean; // false -> no valid session
  adult?: boolean;
  userId?: string;
  llm?: unknown; // value returned by llmJson; omit for null
  flagged?: boolean | ((text: string) => boolean);
  transcript?: string | null;
  env?: Record<string, string>;
  upsertError?: boolean;
  deleteError?: boolean;
}

export interface Harness {
  deps: Deps;
  calls: Call[]; // calls on the user's Supabase client
  adminCalls: Call[]; // calls made with the service role client
  llmCalls: { system: string; user: string }[];
  flaggedCalls: string[];
}

export const USER_ID = "11111111-1111-1111-1111-111111111111";

export function makeDeps(o: HarnessOpts = {}): Harness {
  const { client, calls } = fakeSupabase(o.sb);
  const adminCalls: Call[] = [];
  const llmCalls: { system: string; user: string }[] = [];
  const flaggedCalls: string[] = [];
  const userId = o.userId ?? USER_ID;

  const deps: Deps = {
    authed: async () =>
      o.authed === false ? null : ({ supabase: client, user: { id: userId, email: "u@example.com" }, adult: o.adult ?? true } as Ctx),
    llmJson: async (system, user) => {
      llmCalls.push({ system, user });
      return o.llm ?? null;
    },
    flagged: async (text) => {
      flaggedCalls.push(text);
      return typeof o.flagged === "function" ? o.flagged(text) : (o.flagged ?? false);
    },
    transcribe: async () => (o.transcript === undefined ? "Hello this is a test of my voice and I would like to say something nice" : o.transcript),
    admin: () => ({
      auth: {
        admin: {
          deleteUser: async (id: string) => {
            adminCalls.push({ op: "deleteUser", payload: id });
            return { error: o.deleteError ? { message: "boom" } : null };
          },
        },
      },
      rpc: async (name, args) => {
        adminCalls.push({ op: "rpc", name, payload: args });
        return { data: null, error: null };
      },
      from: (table: string) => ({
        // deno-lint-ignore no-explicit-any
        upsert: async (row: any, options: any) => {
          adminCalls.push({ op: "upsert", table, payload: { row, options } });
          return { error: o.upsertError ? { message: "db down" } : null };
        },
        // deno-lint-ignore no-explicit-any
        insert: async (row: any) => {
          adminCalls.push({ op: "insert", table, payload: row });
          return { error: null };
        },
      }),
    }),
    env: (name) => o.env?.[name],
  };
  return { deps, calls, adminCalls, llmCalls, flaggedCalls };
}

export const post = (body: unknown, headers: Record<string, string> = { Authorization: "Bearer test" }) =>
  new Request("http://localhost/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

export const rpcCalls = (calls: Call[], name: string) => calls.filter((c) => c.op === "rpc" && c.name === name);
export const inserts = (calls: Call[], table: string) => calls.filter((c) => c.op === "insert" && c.table === table);
