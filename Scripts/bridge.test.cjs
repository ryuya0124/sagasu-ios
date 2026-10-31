const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const source = readFileSync("AndroidFind/Resources/FindHubBridge.js", "utf8");

function inventory() {
  const row = [
    [["test-device-id"], 1],
    [],
    [],
    null,
    "Test Phone",
    ["https://example.com/phone.png"],
  ];
  return [null, [row], [2, null, 2]];
}

function harness({
  data = inventory(),
  host = "www.google.com",
  search = "",
  fetch,
  initialEmail,
} = {}) {
  const messages = [];
  const intervals = new Map();
  const state = { buttons: [], marker: null, info: null, dialogs: [] };
  if (initialEmail)
    state.buttons = [
      {
        textContent: "",
        querySelector: () => null,
        getAttribute: (key) =>
          key === "aria-label" ? `Google アカウント: Test User (${initialEmail})` : null,
      },
    ];
  let sequence = 0;
  let observer;
  const document = {
    scripts: [
      {
        textContent: `AF_initDataCallback({key: 'ds:0', data:${JSON.stringify(data)}, sideChannel: {}});`,
      },
    ],
    documentElement: {},
    querySelector(selector) {
      if (selector === '[jscontroller="yADMQb"]') return state.info;
      return null;
    },
    querySelectorAll(selector) {
      if (selector.includes('[role="dialog"]')) return state.dialogs;
      if (selector.includes("data-location-lat")) return state.marker ? [state.marker] : [];
      if (selector === 'button, [role="button"]') return state.buttons;
      return [];
    },
  };
  const context = {
    location: { protocol: "https:", hostname: host, pathname: "/android/find/", search },
    document,
    URLSearchParams,
    fetch,
    setTimeout: (fn) => {
      fn();
      return 1;
    },
    clearTimeout() {},
    setInterval: (fn) => {
      intervals.set(++sequence, fn);
      return sequence;
    },
    clearInterval: (id) => intervals.delete(id),
    MutationObserver: class {
      constructor(fn) {
        observer = fn;
      }
      observe() {}
    },
  };
  context.window = {
    webkit: { messageHandlers: { findHub: { postMessage: (message) => messages.push(message) } } },
    WIZ_global_data: {
      SNlM0e: "test-csrf-do-not-export",
      FdrFJe: "test-session",
      cfb2h: "test-build",
    },
  };
  vm.runInNewContext(source, context);
  return {
    messages,
    state,
    context,
    command: (command) => context.window.AndroidFindBridge.command(command),
    tick: () => [...intervals.values()].forEach((fn) => fn()),
    mutate: () => observer(),
  };
}

function detail(name) {
  return {
    textContent: `${name}最終検知: たった今Wi-Fi85%`,
    querySelector(selector) {
      if (selector === "img[alt]") return { getAttribute: () => name };
      if (selector === "#location-text") return { textContent: "最終検知: たった今" };
      return null;
    },
  };
}

test("bootstrap projects the observed inventory schema without IDs, keys or tokens beyond device ID", () => {
  const h = harness();
  assert.equal(h.messages.length, 1);
  assert.equal(h.messages[0].devices[0].name, "Test Phone");
  assert.equal(h.messages[0].devices[0].id, "test-device-id");
  assert.equal(h.messages[0].devices[0].slot, undefined);
  assert.ok(!JSON.stringify(h.messages).includes("test-csrf"));
});

test("the signed-in account is announced before inventory and every event is account-tagged", () => {
  const h = harness({ initialEmail: "First@Example.com" });
  assert.equal(h.messages[0].type, "account");
  assert.equal(h.messages[0].email, "first@example.com");
  assert.equal(h.messages[1].type, "devices");
  assert.equal(h.messages[1].accountEmail, "first@example.com");
  h.state.buttons = [
    {
      textContent: "",
      querySelector: () => null,
      getAttribute: () => "Google Account: Second (second@example.com)",
    },
  ];
  h.mutate();
  assert.equal(h.messages.at(-1).type, "account");
  assert.equal(h.messages.at(-1).accountEmail, "second@example.com");
});

test("does not run on Google sign-in origin", () => {
  const h = harness({ host: "accounts.google.com" });
  assert.equal(h.context.window.AndroidFindBridge, undefined);
  assert.equal(h.messages.length, 0);
});

test("malformed inventory is not represented as an empty signed-in account", () => {
  const h = harness({ data: [null, [["unexpected"]]] });
  assert.equal(h.messages.length, 0);
  const empty = harness({ data: [null, []] });
  assert.equal(empty.messages[0].devices.length, 0);
});

test("browser RPC sends the observed method and decodes XSSI-framed response", async () => {
  let request;
  const h = harness({
    fetch: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        text: async () =>
          `)]}'\n\n123\n${JSON.stringify([["wrb.fr", "oMJvue", JSON.stringify(inventory())]])}\n`,
      };
    },
  });
  h.command({ command: "refreshDevices" });
  await new Promise((resolve) => setImmediate(resolve));
  assert.ok(request.url.startsWith("/android/find/_/BoqWebFindMyDeviceUi/data/batchexecute?"));
  const params = request.options.body;
  const batch = JSON.parse(params.get("f.req"));
  assert.equal(batch[0][0][0], "oMJvue");
  assert.deepEqual(JSON.parse(batch[0][0][1]), [[1], null, null, 1, [1, 5, 2]]);
  assert.equal(request.options.credentials, "same-origin");
  assert.equal(h.messages.filter((m) => m.type === "devices").length, 2);
  assert.ok(!JSON.stringify(h.messages).includes("test-csrf"));
});

test("position comes from the selected device marker and preserves zero coordinates", () => {
  const h = harness();
  h.state.info = detail("Test Phone");
  const attrs = {
    "data-slot-id": "0",
    "data-active": "true",
    "data-location-lat": "0",
    "data-location-lng": "0",
  };
  h.state.marker = { getAttribute: (key) => attrs[key] };
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  const location = h.messages.find((m) => m.type === "location");
  assert.equal(location.latitude, 0);
  assert.equal(location.longitude, 0);
  assert.equal(location.lastSeen, "たった今");
  h.state.marker = { getAttribute: (key) => ({ ...attrs, "data-slot-id": "99" })[key] };
  h.mutate();
  assert.equal(h.messages.filter((m) => m.type === "location").length, 1);
});

test("access-token sessions can refresh inventory without exporting the credential", async () => {
  const token = "synthetic-embedded-session-token";
  const h = harness({
    search: `?access_token=${token}`,
    fetch: async (url) => {
      const query = new URLSearchParams(url.split("?")[1]);
      if (query.get("access_token") !== token) return { ok: false };
      return {
        ok: true,
        text: async () =>
          `)]}'\n\n123\n${JSON.stringify([["wrb.fr", "oMJvue", JSON.stringify(inventory())]])}\n`,
      };
    },
  });
  h.command({ command: "refreshDevices" });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(h.messages.filter((m) => m.type === "devices").length, 2);
  assert.equal(h.messages.filter((m) => m.type === "error").length, 0);
  assert.ok(!JSON.stringify(h.messages).includes(token));
});

test("ringing rejects the wrong selected device and does not report success on click", () => {
  const h = harness();
  let clicks = 0;
  h.state.info = detail("A different phone");
  h.state.buttons = [
    {
      textContent: "音を鳴らす",
      getAttribute: () => "",
      querySelector: () => null,
      click: () => clicks++,
    },
  ];
  h.command({ command: "ring", id: "test-device-id" });
  assert.equal(clicks, 0);
  h.state.info = detail("Test Phone");
  h.state.marker = {
    getAttribute: (key) =>
      ({
        "data-slot-id": "0",
        "data-active": "true",
        "data-location-lat": "35",
        "data-location-lng": "139",
      })[key],
  };
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  h.command({ command: "ring", id: "test-device-id" });
  assert.equal(clicks, 1);
  assert.equal(h.messages.filter((m) => m.type === "sound" && m.playing).length, 0);
  h.state.buttons = [
    {
      textContent: "音の再生を停止",
      getAttribute: () => "",
      querySelector: () => null,
      click() {},
    },
  ];
  h.tick();
  assert.equal(h.messages.find((m) => m.type === "sound" && m.playing).playing, true);
});

test("rapid device switches cancel the previous queued row selection", () => {
  const data = inventory();
  const second = JSON.parse(JSON.stringify(data[1][0]));
  second[0][0][0] = "second-device";
  second[4] = "Second Phone";
  data[1].push(second);
  const h = harness({ data });
  const clicks = [];
  h.state.buttons = ["Test Phone", "Second Phone"].map((name) => ({
    textContent: name,
    getAttribute: () => "",
    querySelector: (selector) => (selector === 'img[alt="Device image"]' ? {} : null),
    click: () => clicks.push(name),
  }));
  h.command({ command: "select", id: "test-device-id" });
  h.command({ command: "select", id: "second-device" });
  h.tick();
  assert.deepEqual(clicks, ["Second Phone"]);
});

test("device switches use the detail Back button instead of the Google shell back control", () => {
  const data = inventory();
  const second = JSON.parse(JSON.stringify(data[1][0]));
  second[0][0][0] = "second-device";
  second[4] = "Second Phone";
  data[1].push(second);
  const h = harness({ data });
  let shellClicks = 0;
  let backClicks = 0;
  const clicks = [];
  const rows = ["Test Phone", "Second Phone"].map((name) => ({
    textContent: name,
    getAttribute: () => "",
    querySelector: (selector) => (selector === 'img[alt="Device image"]' ? {} : null),
    click: () => clicks.push(name),
  }));
  h.state.info = detail("Test Phone");
  h.state.buttons = [
    {
      textContent: "",
      getAttribute: () => "戻る",
      querySelector: () => null,
      click: () => shellClicks++,
    },
    {
      textContent: "arrow_back",
      getAttribute: () => "Back",
      querySelector: () => null,
      click: () => {
        backClicks++;
        h.state.buttons = rows;
      },
    },
  ];
  h.command({ command: "select", id: "second-device" });
  h.tick();
  assert.equal(shellClicks, 0);
  assert.equal(backClicks, 1);
  assert.deepEqual(clicks, ["Second Phone"]);
});

test("closing the detail cancels pending selection and sound authorization", () => {
  const h = harness();
  let clicks = 0;
  h.state.buttons = [
    {
      textContent: "Test Phone",
      getAttribute: () => "",
      querySelector: () => ({}),
      click: () => clicks++,
    },
  ];
  h.command({ command: "select", id: "test-device-id" });
  h.command({ command: "cancelSelection" });
  h.tick();
  assert.equal(clicks, 0);
  h.command({ command: "ring", id: "test-device-id" });
  assert.equal(clicks, 0);
  assert.equal(h.messages.at(-1).operation, "sound");
  assert.equal(h.messages.at(-1).id, "test-device-id");
});

test("sound confirmation from another device is never accepted", () => {
  const h = harness();
  h.state.info = detail("Test Phone");
  h.state.marker = {
    getAttribute: (key) =>
      ({
        "data-slot-id": "0",
        "data-active": "true",
        "data-location-lat": "35",
        "data-location-lng": "139",
      })[key],
  };
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  h.state.buttons = [
    { textContent: "音を鳴らす", getAttribute: () => "", querySelector: () => null, click() {} },
  ];
  h.command({ command: "ring", id: "test-device-id" });
  h.state.info = detail("Another Phone");
  h.state.buttons = [
    {
      textContent: "音の再生を停止",
      getAttribute: () => "",
      querySelector: () => null,
      click() {},
    },
  ];
  h.tick();
  assert.equal(h.messages.filter((m) => m.type === "sound" && m.playing).length, 0);
});

test("inventory failures are identified separately from location and sound errors", async () => {
  const h = harness({ fetch: async () => ({ ok: false }) });
  h.command({ command: "refreshDevices" });
  await new Promise((resolve) => setImmediate(resolve));
  const failure = h.messages.find((m) => m.type === "error");
  assert.equal(failure.operation, "inventory");
  assert.equal(failure.id, null);
});

test("existing ringing state is restored from the selected official device view", () => {
  const h = harness();
  h.state.info = detail("Test Phone");
  h.state.marker = {
    getAttribute: (key) =>
      ({
        "data-slot-id": "0",
        "data-active": "true",
        "data-location-lat": "35",
        "data-location-lng": "139",
      })[key],
  };
  h.state.buttons = [
    {
      textContent: "音の再生を停止",
      getAttribute: () => "",
      querySelector: () => null,
      click() {
        throw new Error("state restoration must not click sound controls");
      },
    },
  ];
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  assert.equal(h.messages.find((m) => m.type === "sound" && m.playing)?.id, "test-device-id");
});

test("device metadata uses a whitelist and resolves an unnamed Pixel without exposing opaque fields", () => {
  const data = inventory();
  const row = data[1][0];
  row[4] = "";
  row[2] = [
    null,
    [1700000000, 500000000],
    "Pixel 9",
    "Google",
    "tokay",
    "Test Carrier",
    "123456789012345",
    "ABC123",
  ];
  row[2][22] = "opaque-metadata-secret";
  row[10] = ["private-key-material"];
  row[12] = "opaque-inventory-secret";
  row[1] = [
    [Array.from({ length: 31 }, (_, i) => (i === 30 ? [] : null)), 1],
    [[null, []], 1],
  ];
  const h = harness({ data });
  const device = h.messages[0].devices[0];
  assert.equal(device.name, "Pixel 9");
  assert.equal(device.information.model, "Pixel 9");
  assert.equal(device.information.imei, "123456789012345");
  assert.equal(device.information.firstRegisteredAt, 1700000000.5);
  assert.deepEqual(Array.from(device.information.supportedActions), ["sound", "secure"]);
  assert.ok(!JSON.stringify(h.messages).includes("secret"));
  assert.ok(!JSON.stringify(h.messages).includes("key-material"));
  let clicks = 0;
  h.state.buttons = [
    {
      textContent: "不明なデバイス",
      getAttribute: () => "",
      querySelector: () => ({}),
      click: () => clicks++,
    },
  ];
  h.command({ command: "select", id: device.id });
  h.tick();
  assert.equal(clicks, 1);
  h.state.info = detail("不明なデバイス");
  h.mutate();
  assert.equal(h.messages.find((m) => m.type === "status")?.id, device.id);
});

test("offline details still publish battery, charging and connectivity without fabricating coordinates", () => {
  const h = harness();
  const selectors = {
    "img[alt]": { getAttribute: () => "Test Phone" },
    "#location-text": { textContent: "最終検知: 1時間前" },
    "[data-battery]": { getAttribute: () => "80-charging" },
    '[aria-label^="Wi-Fi"]': {
      getAttribute: () => "4",
      nextElementSibling: { textContent: "Test Wi-Fi" },
    },
    "[data-cellular]": {
      getAttribute: () => "3",
      nextElementSibling: { textContent: "Test Mobile" },
    },
  };
  h.state.info = { textContent: "80%", querySelector: (key) => selectors[key] || null };
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  const state = h.messages.find((m) => m.type === "status");
  assert.equal(state.isCharging, true);
  assert.equal(state.battery, 80);
  assert.equal(state.network, "Test Wi-Fi");
  assert.equal(state.cellularNetwork, "Test Mobile");
  assert.equal(state.wifiSignal, 4);
  assert.equal(state.cellularSignal, 3);
  assert.equal(state.lastSeen, "1時間前");
  assert.equal(h.messages.filter((m) => m.type === "location").length, 0);
});

test("invalid registration timestamp is omitted instead of crashing bootstrap", () => {
  for (const date of [[-1, 0], [1700000000, -1], [1700000000, 1e9], [1e15, 0], "bad"]) {
    const data = inventory();
    data[1][0][2] = [null, date];
    const h = harness({ data });
    assert.equal(h.messages[0].devices[0].information.firstRegisteredAt, null);
  }
});

test("an explicit Google unavailable result never refreshes a stale marker as a new location", () => {
  const h = harness();
  h.state.info = detail("Test Phone");
  h.state.info.textContent = "Test Phone デバイスにアクセスできません";
  h.state.marker = {
    getAttribute: (key) =>
      ({
        "data-slot-id": "0",
        "data-active": "true",
        "data-location-lat": "35",
        "data-location-lng": "139",
      })[key],
  };
  h.command({ command: "select", id: "test-device-id" });
  h.mutate();
  assert.equal(
    h.messages.find((m) => m.type === "status")?.connectionStatus,
    "デバイスにアクセスできません",
  );
  assert.equal(h.messages.filter((m) => m.type === "location").length, 0);
});

function actionHarness({
  action = "lock",
  disabled = false,
  name = "Test Phone",
  data = inventory(),
} = {}) {
  const h = harness({ data, initialEmail: "owner@example.com" });
  const clicks = [];
  const button = {
    disabled,
    getAttribute: () => null,
    getClientRects: () => [{}],
    click: () => {
      clicks.push(action);
      h.state.dialogs.push({ getClientRects: () => [{}] });
    },
  };
  const names = { lock: "LVPyJb", markFound: "SauT1d", erase: "yUVuQe" };
  const entry = {
    matches: () => false,
    querySelector: () => button,
    getAttribute: () => null,
    getClientRects: () => [{}],
    classList: { contains: () => false },
  };
  const info = detail(name);
  info.closest = () => ({
    querySelector: (selector) => (selector === `[jsname="${names[action]}"]` ? entry : null),
  });
  h.state.info = info;
  h.command({ command: "select", id: "test-device-id" });
  const open = (extra = {}) =>
    h.command({
      command: "openDeviceAction",
      id: "test-device-id",
      action,
      expectedAccount: "owner@example.com",
      ...extra,
    });
  return { ...h, open, clicks };
}

test("security actions click exactly one selected-device entry and never confirm the resulting Google dialog", () => {
  for (const action of ["lock", "markFound", "erase"]) {
    const h = actionHarness({ action });
    h.open();
    for (let i = 0; i < 50; i++) h.tick();
    assert.deepEqual(h.clicks, [action]);
    const opened = h.messages.filter((m) => m.type === "deviceActionOpened");
    assert.equal(opened.length, 1);
    assert.equal(opened[0].id, "test-device-id");
    assert.equal(opened[0].action, action);
    assert.equal(
      h.messages.some((m) => m.type === "deviceActionCompleted"),
      false,
    );
  }
});

test("security actions work without a GPS fix but reject the wrong device or account", () => {
  const h = actionHarness();
  h.open({ expectedAccount: "different@example.com" });
  h.tick();
  assert.deepEqual(h.clicks, []);
  h.state.info = detail("Another Phone");
  h.open();
  for (let i = 0; i < 45; i++) h.tick();
  assert.deepEqual(h.clicks, []);
  assert.ok(h.messages.some((m) => m.type === "error" && m.operation === "deviceAction"));
});

test("security actions reject ambiguous duplicate device names, unsupported commands and existing dialogs", () => {
  const data = inventory();
  const duplicate = JSON.parse(JSON.stringify(data[1][0]));
  duplicate[0][0][0] = "another-id";
  data[1].push(duplicate);
  const ambiguous = actionHarness({ data });
  ambiguous.open();
  ambiguous.tick();
  assert.deepEqual(ambiguous.clicks, []);
  const unknown = actionHarness();
  unknown.open({ action: "confirmErase" });
  unknown.tick();
  assert.deepEqual(unknown.clicks, []);
  const dialog = actionHarness({ action: "erase" });
  dialog.state.dialogs = [{ getClientRects: () => [{}] }];
  dialog.open();
  dialog.tick();
  assert.deepEqual(dialog.clicks, []);
});

test("a closed sheet, changed account or disabled card cannot trigger a delayed security action", () => {
  const closed = actionHarness();
  closed.open();
  closed.command({ command: "cancelDeviceAction" });
  closed.tick();
  assert.deepEqual(closed.clicks, []);
  const switched = actionHarness();
  switched.open();
  switched.state.buttons = [
    {
      textContent: "",
      querySelector: () => null,
      getAttribute: () => "Google Account: Another (another@example.com)",
    },
  ];
  switched.tick();
  assert.deepEqual(switched.clicks, []);
  const disabled = actionHarness({ disabled: true });
  disabled.open();
  for (let i = 0; i < 45; i++) disabled.tick();
  assert.deepEqual(disabled.clicks, []);
  assert.ok(disabled.messages.some((m) => m.operation === "deviceAction"));
});

test("marked-lost rows are selected using the exact name while keeping the Lost badge separate", () => {
  const h = harness();
  let selections = 0;
  h.state.buttons = [
    {
      textContent: "Test PhoneLost",
      getAttribute: () => null,
      querySelector: (selector) =>
        selector === 'img[alt="Device image"]'
          ? {}
          : selector === ".KaKp4c"
            ? { textContent: "Test Phone" }
            : null,
      click: () => selections++,
    },
  ];
  h.command({ command: "select", id: "test-device-id" });
  h.tick();
  assert.equal(selections, 1);
  assert.equal(
    h.messages.some((m) => m.type === "error"),
    false,
  );
});
