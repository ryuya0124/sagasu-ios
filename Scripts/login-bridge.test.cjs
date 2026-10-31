const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const source = readFileSync("AndroidFind/Resources/GoogleLoginBridge.js", "utf8");

function harness({ host = "accounts.google.com", path = "/v3/signin/identifier" } = {}) {
  const nodes = new Map();
  const writes = [];
  const messages = [];
  const accounts = [];
  const lists = new Map();
  class Input {
    constructor() {
      this.disabled = false;
      this.shown = true;
    }
    get value() {
      throw new Error("Password and OTP values must never be read");
    }
    set value(value) {
      writes.push(value);
    }
    getClientRects() {
      return this.shown ? [{}] : [];
    }
    dispatchEvent() {}
    getAttribute(name) {
      return name === "aria-invalid" && this.invalid ? "true" : null;
    }
  }
  const next = {
    disabled: false,
    clicks: 0,
    getClientRects: () => [{}],
    click() {
      this.clicks++;
    },
  };
  const context = {
    location: { protocol: "https:", hostname: host, pathname: path },
    document: {
      documentElement: {},
      querySelector: (s) => nodes.get(s) || null,
      querySelectorAll: (s) => (s === "[data-identifier]" ? accounts : lists.get(s) || []),
    },
    HTMLInputElement: Input,
    Event: class {},
    MutationObserver: class {
      constructor() {}
      observe() {}
    },
    clearTimeout() {},
    setTimeout(fn) {
      fn();
    },
    window: {
      webkit: { messageHandlers: { googleLogin: { postMessage: (m) => messages.push(m) } } },
    },
  };
  vm.runInNewContext(source, context);
  return {
    context,
    nodes,
    writes,
    messages,
    accounts,
    lists,
    next,
    Input,
    step: (email = "person@example.com", password = "", submitted = []) =>
      context.window.AndroidFindLogin.step(email, password, submitted),
  };
}

test("the login adapter never runs outside the exact Google accounts origin", () => {
  for (const host of ["www.google.com", "accounts.google.com.evil.example", "evil.example"]) {
    const h = harness({ host });
    assert.equal(h.context.window.AndroidFindLogin, undefined);
  }
});

test("the identifier is submitted once without reading or exporting a password", () => {
  const h = harness();
  h.nodes.set('input#identifierId[name="identifier"]', new h.Input());
  h.nodes.set("#identifierNext button", h.next);
  assert.equal(h.step(), "identifier");
  assert.deepEqual(h.writes, ["person@example.com"]);
  assert.equal(h.step("person@example.com", "", ["identifier"]), "waiting");
  assert.equal(h.next.clicks, 1);
  assert.equal(h.messages.length, 1);
  assert.equal(h.messages[0].type, "pageChanged");
});

test("password insertion requires an exact visible Google account match and a separate password request", () => {
  const h = harness({ path: "/v3/signin/challenge/pwd" });
  h.nodes.set('input[type="password"][name="Passwd"]', new h.Input());
  h.nodes.set("#passwordNext button", h.next);
  h.nodes.set("#profileIdentifier", { textContent: "other@example.com", getAttribute: () => null });
  assert.equal(h.step("person@example.com", "synthetic-password"), "accountMismatch");
  assert.deepEqual(h.writes, []);
  h.nodes.set("#profileIdentifier", {
    textContent: "Person@Example.com",
    getAttribute: () => null,
  });
  assert.equal(h.step(), "passwordNeeded");
  assert.deepEqual(h.writes, []);
  assert.equal(h.step("person@example.com", "synthetic-password"), "password");
  assert.deepEqual(h.writes, ["synthetic-password"]);
  assert.equal(h.step("person@example.com", "synthetic-password", ["password"]), "waiting");
  assert.equal(h.next.clicks, 1);
  assert.ok(!JSON.stringify(h.messages).includes("synthetic-password"));
});

test("MFA, passkeys, CAPTCHA and account recovery remain manual even if a password form is present", () => {
  for (const challenge of ["totp", "ipp", "selection", "recaptcha", "dp", "pk", "ootp"]) {
    const h = harness({ path: "/v3/signin/challenge/" + challenge });
    h.nodes.set('input[type="password"][name="Passwd"]', new h.Input());
    h.nodes.set("#passwordNext button", h.next);
    assert.equal(h.step("person@example.com", "synthetic-password", ["password"]), "manual");
    assert.equal(h.next.clicks, 0);
    assert.deepEqual(h.writes, []);
  }
  const other = harness({ path: "/ChangePasswd" });
  assert.equal(other.step("person@example.com", "synthetic-password"), "manual");
});

test("account selection accepts only one exact saved account and never a different or ambiguous row", () => {
  const h = harness({ path: "/AccountChooser" });
  const row = (email) => ({
    getAttribute: () => email,
    getClientRects: () => [{}],
    click: () => h.next.clicks++,
  });
  h.accounts.push(row("other@example.com"));
  assert.equal(h.step(), "manual");
  assert.equal(h.next.clicks, 0);
  h.accounts.push(row("person@example.com"));
  assert.equal(h.step(), "account");
  assert.equal(h.next.clicks, 1);
  h.accounts.push(row("person@example.com"));
  assert.equal(h.step(), "manual");
  assert.equal(h.next.clicks, 1);
});

test("hidden fields and disabled buttons cannot receive or submit saved credentials", () => {
  const h = harness();
  const input = new h.Input();
  input.shown = false;
  h.nodes.set('input#identifierId[name="identifier"]', input);
  h.nodes.set("#identifierNext button", h.next);
  h.step();
  assert.deepEqual(h.writes, []);
  input.shown = true;
  h.next.disabled = true;
  assert.equal(h.step(), "manual");
  assert.deepEqual(h.writes, []);
  assert.equal(h.next.clicks, 0);
});

test("an explicit wrong-password response stops further automatic submissions", () => {
  const h = harness({ path: "/v3/signin/challenge/pwd" });
  const input = new h.Input();
  input.invalid = true;
  h.nodes.set('input[type="password"][name="Passwd"]', input);
  h.nodes.set("#profileIdentifier", {
    textContent: "person@example.com",
    getAttribute: () => null,
  });
  h.nodes.set("#passwordNext button", h.next);
  assert.equal(
    h.step("person@example.com", "synthetic-password", ["password"]),
    "passwordRejected",
  );
  assert.deepEqual(h.writes, []);
  assert.equal(h.next.clicks, 0);
});

test("a first-factor passkey preference can switch only to the exact Google password method", () => {
  const h = harness({ path: "/v3/signin/challenge/selection" });
  h.nodes.set('input#identifierId[type="hidden"]', { value: "person@example.com" });
  const method = { getClientRects: () => [{}], click: () => h.next.clicks++ };
  h.lists.set('[data-challengetype="1"]', [method]);
  assert.equal(h.step(), "passwordMethod");
  assert.equal(h.next.clicks, 1);
  assert.equal(h.step("person@example.com", "", ["password"]), "manual");
  assert.equal(h.next.clicks, 1);
  assert.equal(h.step("other@example.com"), "accountMismatch");
  assert.equal(h.next.clicks, 1);
  h.lists.set('[data-challengetype="1"]', [method, method]);
  assert.equal(h.step(), "manual");
  assert.equal(h.next.clicks, 1);
});

test("the first-factor passkey page can open alternatives once without activating a passkey or MFA", () => {
  const h = harness({ path: "/v3/signin/challenge/pk/presend" });
  h.nodes.set('input#identifierId[type="hidden"]', { value: "person@example.com" });
  h.lists.set('button,[role="button"],a', [
    { textContent: "別の方法を試す", getClientRects: () => [{}], click: () => h.next.clicks++ },
  ]);
  assert.equal(h.step(), "alternative");
  assert.equal(h.next.clicks, 1);
  assert.equal(h.step("person@example.com", "", ["alternative"]), "manual");
  assert.equal(h.next.clicks, 1);
  assert.equal(h.step("person@example.com", "", ["password"]), "manual");
  assert.equal(h.next.clicks, 1);
});
