// Dependencies injected into handlers. Production wiring is in each function's index.ts;
// tests pass fakes (see testing.ts), so handlers can be tested without network, AI or database.
export interface Ctx {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  user: { id: string; email?: string | null };
  adult: boolean;
}

export interface AdminLike {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<unknown>;
  auth: { admin: { deleteUser(id: string): PromiseLike<{ error: unknown }> } };
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
}

export interface Deps {
  authed(req: Request): Promise<Ctx | null>;
  // deno-lint-ignore no-explicit-any
  llmJson(system: string, user: string, maxTokens?: number): Promise<any>;
  flagged(text: string): Promise<boolean>;
  transcribe(blob: Blob, filename?: string): Promise<string | null>;
  admin(): AdminLike;
  env(name: string): string | undefined;
}
