import { assertEquals } from "jsr:@std/assert@1";
import { makeDeps, post, USER_ID } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

Deno.test("delete-account: needs a session, a POST and the typed confirmation", async () => {
  assertEquals((await makeHandler(makeDeps({ authed: false }).deps)(post({ confirm: "DELETE" }))).status, 401);
  const hz = makeDeps();
  const h = makeHandler(hz.deps);
  assertEquals((await h(new Request("http://x", { method: "GET" }))).status, 405);
  assertEquals((await h(post({}))).status, 400);
  assertEquals((await h(post({ confirm: "delete" }))).status, 400);
  assertEquals(hz.adminCalls.length, 0);
});

Deno.test("delete-account: deletes exactly the caller's own account with the service role", async () => {
  const hz = makeDeps();
  const res = await makeHandler(hz.deps)(post({ confirm: "DELETE" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true });
  assertEquals(hz.adminCalls, [{ op: "deleteUser", payload: USER_ID }]);
});

Deno.test("delete-account: a failing deletion returns 502", async () => {
  const hz = makeDeps({ deleteError: true });
  assertEquals((await makeHandler(hz.deps)(post({ confirm: "DELETE" }))).status, 502);
});
