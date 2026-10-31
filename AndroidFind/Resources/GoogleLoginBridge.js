/* Consented automatic sign-in. Credentials arrive only as WKWebView call arguments.
 * Reads account identity and form structure; never reads password/OTP field values.
 * No MFA, CAPTCHA, consent, recovery or security-check buttons are submitted.
 */
(() => {
  "use strict";
  if (
    location.protocol !== "https:" ||
    location.hostname !== "accounts.google.com" ||
    (location.port && location.port !== "443")
  )
    return;
  const allowedPath = () =>
    /^\/(?:v[23]\/)?signin\//.test(location.pathname) ||
    /^\/(ServiceLogin|AccountChooser)(\/|$)/.test(location.pathname);
  const normalize = (value) => (typeof value === "string" ? value.trim().toLowerCase() : "");
  const visible = (element) => !!element && element.getClientRects().length > 0;
  const accountEmail = () => {
    const profile = document.querySelector("#profileIdentifier");
    const identifier = document.querySelector('input#identifierId[type="hidden"]');
    const candidate =
      profile?.getAttribute("data-email") ||
      profile?.textContent?.trim() ||
      identifier?.value ||
      "";
    return normalize(candidate);
  };
  function submit(input, value, button) {
    if (!visible(input) || !visible(button) || input.disabled || button.disabled) return false;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    button.click();
    return true;
  }
  window.AndroidFindLogin = {
    step(email, password, submitted) {
      if (!allowedPath()) return "manual";
      email = normalize(email);
      if (!email || !Array.isArray(submitted)) return "manual";
      // OAuth blocking, MFA and recovery challenges always return control to the user.
      if (
        /\/challenge\//.test(location.pathname) &&
        !/\/challenge\/pwd(?:\/|$)/.test(location.pathname)
      ) {
        // Google may prefer a passkey before the first factor. Use its offered password
        // method only before a password has been submitted, never for a later MFA challenge.
        if (submitted.includes("password")) return "manual";
        if (!/\/challenge\/(pk\/presend|selection)$/.test(location.pathname)) return "manual";
        if (accountEmail() !== email) return "accountMismatch";
        if (/\/pk\/presend$/.test(location.pathname) && !submitted.includes("alternative")) {
          const alternatives = [...document.querySelectorAll('button,[role="button"],a')].filter(
            (e) => visible(e) && /^(別の方法を試す|Try another way)$/.test(e.textContent.trim()),
          );
          if (alternatives.length === 1) {
            alternatives[0].click();
            return "alternative";
          }
        }
        if (/\/selection$/.test(location.pathname) && !submitted.includes("passwordMethod")) {
          const methods = [...document.querySelectorAll('[data-challengetype="1"]')].filter(
            visible,
          );
          if (methods.length === 1) {
            methods[0].click();
            return "passwordMethod";
          }
        }
        return "manual";
      }
      const identifier = document.querySelector('input#identifierId[name="identifier"]');
      if (visible(identifier)) {
        if (submitted.includes("identifier")) return "waiting";
        const next = document.querySelector("#identifierNext button");
        return submit(identifier, email, next) ? "identifier" : "manual";
      }
      const field = document.querySelector('input[type="password"][name="Passwd"]');
      if (visible(field)) {
        if (accountEmail() !== email) return "accountMismatch";
        if (submitted.includes("password"))
          return field.getAttribute("aria-invalid") === "true" ? "passwordRejected" : "waiting";
        if (typeof password !== "string" || !password) return "passwordNeeded";
        const next = document.querySelector("#passwordNext button");
        return submit(field, password, next) ? "password" : "manual";
      }
      const accounts = [...document.querySelectorAll("[data-identifier]")];
      const exact = accounts.filter(
        (element) =>
          normalize(element.getAttribute("data-identifier")) === email && visible(element),
      );
      if (exact.length === 1 && !submitted.includes("account")) {
        exact[0].click();
        return "account";
      }
      if (accounts.length) return "manual";
      return "waiting";
    },
  };
  let timer;
  const announce = () => {
    clearTimeout(timer);
    timer = setTimeout(
      () => window.webkit?.messageHandlers?.googleLogin?.postMessage({ type: "pageChanged" }),
      500,
    );
  };
  new MutationObserver(announce).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  announce();
})();
