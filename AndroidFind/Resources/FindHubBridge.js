/* Google Find Hub browser adapter, observed 2026-10-30.
 * Scope: www.google.com/android/find only. Never runs on account/password pages.
 * Inventory: oMJvue batchexecute RPC. Location: official Punctual/E2EE client -> DOM.
 * No cookie, token, password or key material is sent to the Swift message handler.
 */
(() => {
  "use strict";
  if (
    location.protocol !== "https:" ||
    location.hostname !== "www.google.com" ||
    !location.pathname.startsWith("/android/find")
  )
    return;
  if (window.AndroidFindBridge) return;

  let devices = [];
  let selected = null;
  let confirmedSelection = null;
  let lastLocation = "";
  let lastStatus = "";
  let lastSound = "";
  let scanTimer;
  let ringTimer;
  let selectionTimer;
  let ringingID = null;
  let accountEmail = null;
  let actionTimer;
  const stopSoundPattern = /音.*停止|停止.*音|着信音を停止|Stop (ringing|sound)/i;
  const post = (payload) =>
    window.webkit?.messageHandlers?.findHub?.postMessage({ ...payload, accountEmail });
  const error = (message, operation = "general", id = null) =>
    post({ type: "error", message, operation, id });
  const text = (element) => (element?.textContent || "").trim();
  const detailName = (element) => element?.querySelector("img[alt]")?.getAttribute("alt") || "";
  const buttonText = (element) =>
    [element.getAttribute("aria-label"), text(element)].filter(Boolean).join(" ");
  const buttons = () => [...document.querySelectorAll('button, [role="button"]')];
  function scanAccount() {
    const account = buttons().find((button) =>
      /Google (アカウント|Account):/i.test(button.getAttribute("aria-label") || ""),
    );
    const match = account?.getAttribute("aria-label")?.match(/\(([^()\s]+@[^()\s]+)\)/);
    const email = match?.[1]?.toLowerCase();
    if (!email || email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return;
    if (email !== accountEmail) {
      cancelDeviceAction();
      cancelSelection();
      accountEmail = email;
      post({ type: "account", email });
    }
  }
  const string = (value) => (typeof value === "string" && value.trim() ? value.trim() : null);
  function timestamp(value) {
    if (
      !Array.isArray(value) ||
      !Number.isSafeInteger(value[0]) ||
      value[0] <= 0 ||
      !Number.isInteger(value[1]) ||
      value[1] < 0 ||
      value[1] >= 1e9
    )
      return null;
    const seconds = value[0] + value[1] / 1e9;
    return seconds < 253402300800 ? seconds : null;
  }
  function information(row) {
    const details = Array.isArray(row[2]) ? row[2] : [];
    const commands = Array.isArray(row[1]) ? row[1].map((entry) => entry?.[0]) : [];
    const has = (field) =>
      commands.some((command) => Array.isArray(command) && command[field - 1] != null);
    // Whitelist only fields whose meanings were checked against the current Google client.
    // Sparse command fields are protobuf oneofs, not the trailing numeric enums.
    return {
      model: string(details[2]),
      manufacturer: string(details[3]),
      codeName: string(details[4]),
      carrier: string(details[5]),
      imei: string(details[6]),
      meid: string(details[7]),
      firstRegisteredAt: timestamp(details[1]),
      supportedActions: [
        has(1) || has(31) || has(32) || has(5) ? "sound" : null,
        has(2) || has(3) ? "secure" : null,
        has(6) ? "erase" : null,
        has(7) ? "rename" : null,
      ].filter(Boolean),
    };
  }

  function parseInventory(data) {
    if (!Array.isArray(data) || !Array.isArray(data[1])) return null;
    const result = [];
    for (const [index, row] of data[1].entries()) {
      if (!Array.isArray(row) || !Array.isArray(row[0])) continue;
      const id = row[0]?.[0]?.[0];
      if (typeof id !== "string" || !id) continue;
      const webName = string(row[4]) || "不明なデバイス";
      const metadata = information(row);
      const name = string(row[4]) || metadata.model || webName;
      const lower = name.toLowerCase();
      const kind = /watch|ウォッチ/.test(lower)
        ? "watch"
        : /buds|イヤホン/.test(lower)
          ? "earbuds"
          : /tablet|タブレット|pad/.test(lower)
            ? "tablet"
            : "phone";
      result.push({
        id,
        name,
        webName,
        kind,
        imageURL: string(row[5]?.[0]),
        information: metadata,
        slot: String(index),
      });
    }
    // Fail closed if the schema changes; an actual empty list is valid.
    if (data[1].length && !result.length) return null;
    return result;
  }

  function publishInventory(data) {
    const parsed = parseInventory(data);
    if (parsed === null) return false;
    devices = parsed;
    scanAccount();
    post({ type: "devices", devices: parsed.map(({ slot, webName, ...rest }) => rest) });
    return true;
  }

  function bootstrap() {
    for (const script of document.scripts) {
      if (!script.textContent.startsWith("AF_initDataCallback")) continue;
      const match = script.textContent.match(/data:([\s\S]*), sideChannel:/);
      if (!match) continue;
      try {
        if (publishInventory(JSON.parse(match[1]))) return true;
      } catch (_) {
        /* Not our dataset. */
      }
    }
    return false;
  }

  function decodeBatch(body, rpc) {
    // Google frames the JSON with a length and anti-XSSI prefix. Do not eval it.
    for (const line of body.split("\n")) {
      if (!line.startsWith("[")) continue;
      let rows;
      try {
        rows = JSON.parse(line);
      } catch (_) {
        continue;
      }
      for (const row of rows) {
        if (row?.[0] === "wrb.fr" && row[1] === rpc && typeof row[2] === "string") {
          return JSON.parse(row[2]);
        }
      }
    }
    throw new Error("Unsupported batch response");
  }

  async function refreshDevices() {
    // Tokens stay in the page context and are never exported to the app.
    const config = window.WIZ_global_data;
    if (!config?.SNlM0e) {
      bootstrap();
      return;
    }
    const rpc = "oMJvue";
    const query = new URLSearchParams({ rpcids: rpc, "source-path": location.pathname, rt: "c" });
    if (config.FdrFJe) query.set("f.sid", String(config.FdrFJe));
    if (config.cfb2h) query.set("bl", String(config.cfb2h));
    const sessionParams = new URLSearchParams(location.search);
    const authuser = sessionParams.get("authuser");
    if (authuser) query.set("authuser", authuser);
    // Embedded Google sign-in may authenticate through the entry URL instead of SID cookies.
    const accessToken = sessionParams.get("access_token");
    if (accessToken) query.set("access_token", accessToken);
    const request = [[1], null, null, 1, [1, 5, 2]];
    const form = new URLSearchParams({
      "f.req": JSON.stringify([[[rpc, JSON.stringify(request), null, "generic"]]]),
      at: config.SNlM0e,
    });
    try {
      const response = await fetch(
        `/android/find/_/BoqWebFindMyDeviceUi/data/batchexecute?${query}`,
        {
          method: "POST",
          credentials: "same-origin",
          headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
          body: form,
        },
      );
      if (!response.ok) throw new Error("RPC rejected");
      if (!publishInventory(decodeBatch(await response.text(), rpc)))
        throw new Error("Unknown inventory schema");
    } catch (_) {
      error(
        "デバイス一覧を更新できませんでした。Google画面で接続を確認してください。",
        "inventory",
      );
    }
  }

  function scan() {
    scanAccount();
    if (ringingID && ringingID === selected) {
      const stopped =
        buttons().some((b) => /音を鳴らす|Play sound/i.test(buttonText(b))) &&
        !buttons().some((b) => stopSoundPattern.test(buttonText(b)));
      if (stopped) {
        post({ type: "sound", id: ringingID, playing: false });
        ringingID = null;
      }
    }
    if (!selected) return;
    const device = devices.find((d) => d.id === selected);
    if (!device) return;
    const info = document.querySelector('[jscontroller="yADMQb"]');
    if (!info || detailName(info) !== device.webName) return;
    const batteryIcon = info.querySelector("[data-battery]");
    const batteryState = batteryIcon?.getAttribute("data-battery") || "";
    const batteryMatch = text(info).match(/(\d{1,3})\s*%/);
    const wifi = info.querySelector('[aria-label^="Wi-Fi"]');
    const cellular = info.querySelector("[data-cellular]");
    const signal = (element, attribute) => {
      const value = element?.getAttribute(attribute);
      return value && /^\d+$/.test(value) ? Number(value) : null;
    };
    const status = {
      type: "status",
      id: selected,
      connectionStatus: text(info).includes("デバイスにアクセスできません")
        ? "デバイスにアクセスできません"
        : null,
      battery: batteryMatch ? Number(batteryMatch[1]) : null,
      isCharging: batteryState ? /-charging$/.test(batteryState) : null,
      network: string(wifi?.nextElementSibling?.textContent),
      cellularNetwork: string(cellular?.nextElementSibling?.textContent),
      wifiSignal: signal(wifi, "data-wifi"),
      cellularSignal: signal(cellular, "data-cellular"),
      lastSeen:
        text(info.querySelector("#location-text")).replace(/^最終検知[:：]?\s*/, "") || null,
    };
    const statusFingerprint = JSON.stringify(status);
    if (statusFingerprint !== lastStatus) {
      lastStatus = statusFingerprint;
      post(status);
    }
    if (status.connectionStatus) {
      confirmedSelection = null;
      return;
    }
    const marker = [...document.querySelectorAll("[data-location-lat][data-location-lng]")].find(
      (e) =>
        e.getAttribute("data-slot-id") === device.slot && e.getAttribute("data-active") === "true",
    );
    if (!marker) return;
    const latitude = Number(marker.getAttribute("data-location-lat"));
    const longitude = Number(marker.getAttribute("data-location-lng"));
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      Math.abs(latitude) > 90 ||
      Math.abs(longitude) > 180
    )
      return;
    const payload = { ...status, type: "location", latitude, longitude };
    confirmedSelection = selected;
    const playing = buttons().some((b) => stopSoundPattern.test(buttonText(b)));
    const soundFingerprint = `${selected}:${playing}`;
    if (soundFingerprint !== lastSound) {
      lastSound = soundFingerprint;
      post({ type: "sound", id: selected, playing });
    }
    const fingerprint = JSON.stringify(payload);
    if (fingerprint !== lastLocation) {
      lastLocation = fingerprint;
      post(payload);
    }
  }

  function cancelSelection() {
    cancelDeviceAction();
    clearInterval(selectionTimer);
    selected = null;
    confirmedSelection = null;
    lastLocation = "";
    lastStatus = "";
    lastSound = "";
  }

  function choose(id) {
    clearInterval(selectionTimer);
    const device = devices.find((d) => d.id === id);
    if (!device) {
      error("デバイス一覧を更新してください。", "location", id);
      return;
    }
    const previous = selected;
    selected = id;
    confirmedSelection = null;
    lastLocation = "";
    lastStatus = "";
    lastSound = "";
    const current = document.querySelector('[jscontroller="yADMQb"]');
    if (previous === id && current && detailName(current) === device.webName) {
      scan();
      return;
    }
    // The Google shell also has a Japanese "戻る" button that does not close the
    // device detail. Prefer its own control, then the observed English Back button.
    const back =
      current?.querySelector('[aria-label="Back"], [aria-label="戻る"]') ||
      buttons().find((b) => b.getAttribute("aria-label") === "Back");
    if (back) back.click();
    let attempts = 0;
    selectionTimer = setInterval(() => {
      if (selected !== id) {
        clearInterval(selectionTimer);
        return;
      }
      const rows = buttons().filter((b) => b.querySelector('img[alt="Device image"]'));
      const match = rows[Number(device.slot)];
      // A lost device row also contains a separate "Lost" badge. Match the name node.
      const rowName = text(match?.querySelector(".KaKp4c")) || text(match);
      if (match && rowName !== device.webName) {
        clearInterval(selectionTimer);
        error("デバイス一覧が変更されました。更新してから選択してください。", "location", id);
        return;
      }
      if (match) {
        clearInterval(selectionTimer);
        match.click();
      } else if (++attempts > 30) {
        clearInterval(selectionTimer);
        error("Googleのデバイス選択画面を開いてください。", "location", id);
      }
    }, 150);
  }

  function ring(id) {
    const device = devices.find((d) => d.id === id);
    const current = document.querySelector('[jscontroller="yADMQb"]');
    if (
      !device ||
      confirmedSelection !== id ||
      !current ||
      detailName(current) !== device.webName
    ) {
      error("位置情報の取得が終わってから、もう一度お試しください。", "sound", id);
      return;
    }
    const button = buttons().find((b) => /音を鳴らす|Play sound/i.test(buttonText(b)));
    if (!button) {
      error("このデバイスでは音を鳴らせません。", "sound", id);
      return;
    }
    button.click();
    clearInterval(ringTimer);
    let attempts = 0;
    ringTimer = setInterval(() => {
      const info = document.querySelector('[jscontroller="yADMQb"]');
      const stop =
        info &&
        detailName(info) === device.webName &&
        buttons().find((b) => stopSoundPattern.test(buttonText(b)));
      if (stop) {
        clearInterval(ringTimer);
        ringingID = id;
        post({ type: "sound", id, playing: true });
      } else if (++attempts > 40) {
        clearInterval(ringTimer);
        error(
          "音の再生開始を確認できませんでした。Google画面で状態を確認してください。",
          "sound",
          id,
        );
      }
    }, 500);
  }

  function stopRing(id) {
    const device = devices.find((d) => d.id === id);
    const current = document.querySelector('[jscontroller="yADMQb"]');
    if (
      !device ||
      confirmedSelection !== id ||
      !current ||
      detailName(current) !== device.webName
    ) {
      error("デバイスの接続状態を確認してください。", "sound", id);
      return;
    }
    const button = buttons().find((b) => stopSoundPattern.test(buttonText(b)));
    if (!button) {
      error("音の再生状態を確認できませんでした。", "sound", id);
      return;
    }
    button.click();
    clearInterval(ringTimer);
    let attempts = 0;
    ringTimer = setInterval(() => {
      const info = document.querySelector('[jscontroller="yADMQb"]');
      const play =
        info &&
        detailName(info) === device.webName &&
        buttons().find((b) => /音を鳴らす|Play sound/i.test(buttonText(b)));
      const stop = buttons().find((b) => stopSoundPattern.test(buttonText(b)));
      if (play && !stop) {
        clearInterval(ringTimer);
        ringingID = null;
        post({ type: "sound", id, playing: false });
      } else if (++attempts > 40) {
        clearInterval(ringTimer);
        error("再生停止を確認できませんでした。Google画面を確認してください。", "sound", id);
      }
    }, 500);
  }

  function cancelDeviceAction() {
    clearInterval(actionTimer);
    actionTimer = null;
  }

  function visible(element) {
    return !!element && element.getClientRects().length > 0;
  }
  function hasDialog() {
    return [
      ...document.querySelectorAll('[role="dialog"], [role="alertdialog"], dialog[open]'),
    ].some(visible);
  }

  function openDeviceAction(id, action, expectedAccount) {
    cancelDeviceAction();
    scanAccount();
    const names = { lock: "LVPyJb", markFound: "SauT1d", erase: "yUVuQe" };
    if (!Object.hasOwn(names, action)) {
      error("この操作には対応していません。", "deviceAction", id);
      return;
    }
    const device = devices.find((d) => d.id === id);
    if (
      !device ||
      !accountEmail ||
      expectedAccount !== accountEmail ||
      devices.filter((d) => d.webName === device.webName).length !== 1
    ) {
      error(
        "対象の端末とGoogleアカウントを確認できません。Google画面で確認してください。",
        "deviceAction",
        id,
      );
      return;
    }
    if (hasDialog()) {
      error("Googleで開いている確認画面を閉じてから、もう一度お試しください。", "deviceAction", id);
      return;
    }
    const current = document.querySelector('[jscontroller="yADMQb"]');
    if (selected !== id || !current || detailName(current) !== device.webName) choose(id);
    const owner = accountEmail;
    let attempts = 0;
    actionTimer = setInterval(() => {
      scanAccount();
      const latest = devices.find((d) => d.id === id);
      if (
        selected !== id ||
        owner !== accountEmail ||
        !latest ||
        latest.webName !== device.webName ||
        latest.slot !== device.slot
      ) {
        cancelDeviceAction();
        error(
          "対象の端末またはアカウントが変わりました。操作を選び直してください。",
          "deviceAction",
          id,
        );
        return;
      }
      if (hasDialog()) {
        cancelDeviceAction();
        error("Googleの確認画面を確認してください。自動では操作を続けません。", "deviceAction", id);
        return;
      }
      const info = document.querySelector('[jscontroller="yADMQb"]');
      if (info && detailName(info) === device.webName) {
        // The observed detail controller owns both the identity header and action cards.
        // Never search global buttons or a dialog: that could hit a final confirmation.
        const scope = info.closest('[jsaction*="Si6Wze:Kr5QQe"]');
        const entry = scope?.querySelector(`[jsname="${names[action]}"]`);
        const button = entry?.matches('button, [role="button"]')
          ? entry
          : entry?.querySelector('button, [role="button"]');
        if (
          visible(entry) &&
          visible(button) &&
          !button.disabled &&
          button.getAttribute("aria-disabled") !== "true" &&
          entry.getAttribute("aria-disabled") !== "true" &&
          !entry.classList.contains("rnklrb")
        ) {
          cancelDeviceAction();
          button.click(); // Only the entry card. Google's remaining confirmations are manual.
          post({ type: "deviceActionOpened", id, action });
          return;
        }
      }
      if (++attempts >= 40) {
        cancelDeviceAction();
        error(
          action === "markFound"
            ? "この端末の紛失モード解除を開けません。紛失としてマークされているかGoogle画面で確認してください。"
            : "この端末では操作を開けません。Google画面で対応状況を確認してください。",
          "deviceAction",
          id,
        );
      }
    }, 250);
  }

  window.AndroidFindBridge = {
    command({ command, id, action, expectedAccount }) {
      if (command === "openDeviceAction") openDeviceAction(id, action, expectedAccount);
      if (command === "cancelDeviceAction") cancelDeviceAction();
      if (command === "refreshDevices") refreshDevices();
      if (command === "select") choose(id);
      if (command === "cancelSelection") cancelSelection();
      if (command === "refresh") {
        const device = devices.find((d) => d.id === id);
        const info = document.querySelector('[jscontroller="yADMQb"]');
        if (!device || selected !== id || !info || detailName(info) !== device.webName) {
          choose(id);
          return;
        }
        lastLocation = "";
        const refresh = document.querySelector('button[jsname="jggqnd"]');
        if (refresh) refresh.click();
        scan();
      }
      if (command === "ring") ring(id);
      if (command === "stopRing") stopRing(id);
    },
  };

  bootstrap();
  const observer = new MutationObserver(() => {
    clearTimeout(scanTimer);
    scanTimer = setTimeout(scan, 200);
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      "data-location-lat",
      "data-location-lng",
      "data-active",
      "data-battery",
      "data-wifi",
      "data-cellular",
    ],
  });
})();
