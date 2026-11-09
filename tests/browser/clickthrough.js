// WordCore browser click-through (Playwright). Run by tests/run.py browser.
//   node clickthrough.js <base-url> <site-dir> <screenshot-dir>
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const [base, siteDir, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
let failures = 0;
function check(cond, msg) {
  console.log((cond ? "ok   " : "FAIL ") + msg);
  if (!cond) failures++;
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const problems = [];
  page.on("pageerror", (e) => problems.push("pageerror: " + e.message));
  page.on("console", (m) => {
    const t = m.text();
    // form errors are answered with 401/422 on purpose; browsers log that as a "failed resource"
    if (/Failed to load resource.*status of (401|422)/.test(t)) return;
    if (m.type() === "error" || /Content Security Policy/i.test(t)) problems.push("console: " + t);
  });
  const shot = (name) => page.screenshot({ path: path.join(outDir, name + ".png"), fullPage: true });

  // The program opens this URL itself when double-clicked.
  const code = fs.readFileSync(path.join(siteDir, "setup-code.txt"), "utf8").match(/Setup code: (\S+)/)[1];
  await page.goto(`${base}/setup?code=${code}`);
  check(await page.getByRole("heading", { name: "Name your site" }).isVisible(), "setup opens on step 1 with the code from the URL");
  check(await page.evaluate(() => document.fonts.check("16px Inter")), "Inter font loaded from the program");
  await shot("01-setup-site");

  await page.getByRole("button", { name: "Continue" }).click();
  check(await page.getByText("Give your site a name.").isVisible(), "empty name shows an error next to the field");
  await page.getByLabel("Site name").fill("Nordlys Studio");
  await page.getByLabel("Tagline").fill("Small design studio");
  await page.getByLabel("Time zone").selectOption("Europe/Copenhagen");
  await page.getByRole("button", { name: "Continue" }).click();

  check(await page.getByRole("heading", { name: "Create your account" }).isVisible(), "step 2");
  await page.getByLabel("Username").fill("patrick");
  await page.getByLabel("Your name").fill("Patrick");
  await page.getByLabel("Email").fill("patrick@example.com");
  await page.getByLabel("Password", { exact: true }).fill("weakpass");
  check(await page.locator(".strength").getAttribute("data-score") === "1", "strength meter reacts while typing");
  await page.getByLabel("Password", { exact: true }).fill("Correct-Horse-Battery-9");
  check(Number(await page.locator(".strength").getAttribute("data-score")) >= 3, "strong password scores high");
  await page.getByLabel("Repeat password").fill("Correct-Horse-Battery-9");
  await shot("02-setup-account");
  await page.getByRole("button", { name: "Continue" }).click();

  check(await page.getByRole("heading", { name: "Where is this site running?" }).isVisible(), "step 3");
  check(await page.locator(".choice", { hasText: "This computer" }).getByText("Detected").isVisible(), "this computer detected");
  await page.locator(".choice", { hasText: "VPS or own server" }).click();
  check(await page.locator('input[value="server"]').isChecked(), "clicking a card selects it");
  await page.locator(".choice", { hasText: "This computer" }).click();
  await shot("03-setup-mode");
  await page.getByRole("button", { name: "Continue" }).click();

  check(await page.getByRole("heading", { name: "Pick a starting point" }).isVisible(), "step 4");
  check(await page.locator('input[value="blog"]').isDisabled(), "blog starter disabled until addons exist");
  check(await page.getByLabel("Repository address").inputValue() === "https://wordcore.space/repo/", "official repo filled in");
  await shot("04-setup-start");
  await page.getByRole("button", { name: "Continue" }).click();

  check(await page.getByRole("heading", { name: "Ready to create your site" }).isVisible(), "step 5 summary");
  await page.getByRole("link", { name: "Back" }).click();
  check(await page.getByRole("heading", { name: "Pick a starting point" }).isVisible(), "back goes to step 4 and keeps answers");
  await page.getByRole("button", { name: "Continue" }).click();
  await shot("05-setup-ready");
  await page.getByRole("button", { name: "Create site" }).click();

  check(await page.getByRole("heading", { name: "Dashboard" }).isVisible(), "lands on the dashboard");
  check(await page.getByText("Your site is ready").isVisible(), "welcome message");
  check(await page.getByText("Running locally").isVisible(), "status strip says running locally");
  await shot("06-dashboard");

  await page.getByRole("link", { name: "Settings" }).first().click();
  await page.getByLabel("Site name").fill("Nordlys");
  await page.getByLabel("Trust proxy headers").check();
  await page.getByRole("button", { name: "Save changes" }).click();
  check(await page.getByText("Saved.").isVisible(), "settings saved");
  check(await page.getByLabel("Trust proxy headers").isChecked(), "checkbox kept");
  await shot("07-settings");

  await page.getByRole("link", { name: "Patrick" }).click();
  check(await page.getByRole("heading", { name: "Your account" }).isVisible(), "account page");
  check(await page.getByText("This device").isVisible(), "lists this device");
  await shot("08-account");

  await page.getByRole("link", { name: "View site" }).click();
  check(await page.getByRole("heading", { name: "Nordlys" }).isVisible(), "front page shows the new name");
  await page.goBack();

  await page.getByRole("button", { name: "Log out" }).click();
  check(await page.getByRole("heading", { name: "Sign in" }).isVisible(), "logged out to sign-in page");
  await page.getByLabel("Username or email").fill("patrick");
  await page.getByLabel("Password").fill("wrong-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  check(await page.getByText("Wrong username or password.").isVisible(), "wrong password message");
  await shot("09-login-error");
  await page.getByLabel("Password").fill("Correct-Horse-Battery-9");
  await page.getByRole("button", { name: "Sign in" }).click();
  check(await page.getByRole("heading", { name: "Dashboard" }).isVisible(), "signed back in");

  // dark mode and phone width
  await page.emulateMedia({ colorScheme: "dark" });
  await shot("10-dashboard-dark");
  await page.emulateMedia({ colorScheme: "light" });
  for (const [name, url] of [["dashboard", "/admin"], ["settings", "/admin/settings"], ["account", "/admin/account"]]) {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(base + url);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check(overflow <= 0, `${name} fits a phone screen (overflow ${overflow}px)`);
    if (name === "dashboard") await shot("11-dashboard-phone");
  }
  const login = await (await browser.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  await login.goto(base + "/admin/login");
  check(await login.evaluate(() => document.documentElement.scrollWidth - window.innerWidth) <= 0, "sign-in page fits a phone screen");
  await login.screenshot({ path: path.join(outDir, "12-login-phone.png"), fullPage: true });

  check(problems.length === 0, "no console errors or CSP violations" + (problems.length ? ": " + problems.join(" | ") : ""));
  await browser.close();
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
