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
  check(await page.getByRole("navigation").getByRole("link", { name: "About" }).isVisible(), "starter menu has About");
  await shot("08b-site-home");
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


  // ---------------------------------------------------------------- media upload
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAZKElEQVR42g3PgWoxCgCA0fsQf62UWimllFIrRdM0ERFN0zRN00Q0TURE00QTEU3TNN80EU0T0TRNE00r5Y3uzhuc//6p2FMhUCFUsa9CpEKsQqJCqkKmQq7iQIVChVLFoYojFccqdCoMKkwqLCpOVJyqOFNxruJCxaWKKxVeFX4V1ypuVIRVRFXEVSRV3Kq4U5FVca+ioKKkoqLiQcWjiicVzypeVLyq6KjoqXhT8a5ipGKi4kPFp4ovFd8qVip+VPyq2KrYqfjvn5o9NQI1QjX7akRqxGokaqRqZGrkag7UKNQo1RyqOVJzrEanxqDGpMai5kTNqZozNedqLtRcqrlS41XjV3Ot5kZNWE1UTVxNUs2tmjs1WTX3agpqSmoqah7UPKp5UvOs5kXNq5qOmp6aNzXvakZqJmo+1Hyq+VLzrWal5kfNr5qtmp36L6BhT4NAg1DDvgaRBrEGiQapBpkGuYYDDQoNSg2HGo40HGvQaTBoMGmwaDjRcKrhTMO5hgsNlxquNHg1+DVca7jRENYQ1RDXkNRwq+FOQ1bDvYaChpKGioYHDY8anjQ8a3jR8Kqho6Gn4U3Du4aRhomGDw2fGr40fGtYafjR8Kthq2Gn+Qto2dMi0CLUsq9FpEWsRaJFqkWmRa7lQItCi1LLoZYjLcdadFoMWkxaLFpOtJxqOdNyruVCy6WWKy1eLX4t11putIS1RLXEtSS13Gq505LVcq+loKWkpaLlQcujlictz1petLxq6WjpaXnT8q5lpGWi5UPLp5YvLd9aVlp+tPxq2WrZaf8Cevb0CPQI9ezrEekR65HokeqR6ZHrOdCj0KPUc6jnSM+xHp0egx6THoueEz2nes70nOu50HOp50qPV49fz7WeGz1hPVE9cT1JPbd67vRk9dzrKegp6anoedDzqOdJz7OeFz2vejp6enre9LzrGemZ6PnQ86nnS8+3npWeHz2/erZ6dvq/gJE9IwIjQiP7RkRGxEYkRqRGZEbkRg6MKIwojRwaOTJybERnxGDEZMRi5MTIqZEzI+dGLoxcGrky4jXiN3Jt5MZI2EjUSNxI0sitkTsjWSP3RgpGSkYqRh6MPBp5MvJs5MXIq5GOkZ6RNyPvRkZGJkY+jHwa+TLybWRl5MfIr5GtkZ3xL2Bmz4zAjNDMvhmRGbEZiRmpGZkZuZkDMwozSjOHZo7MHJvRmTGYMZmxmDkxc2rmzMy5mQszl2auzHjN+M1cm7kxEzYTNRM3kzRza+bOTNbMvZmCmZKZipkHM49mnsw8m3kx82qmY6Zn5s3Mu5mRmYmZDzOfZr7MfJtZmfkx82tma2Zn/gtY2bMisCK0sm9FZEVsRWJFakVmRW7lwIrCitLKoZUjK8dWdFYMVkxWLFZOrJxaObNybuXCyqWVKyteK34r11ZurIStRK3ErSSt3Fq5s5K1cm+lYKVkpWLlwcqjlScrz1ZerLxa6VjpWXmz8m5lZGVi5cPKp5UvK99WVlZ+rPxa2VrZWf8CNvZsCGwIbezbENkQ25DYkNqQ2ZDbOLChsKG0cWjjyMaxDZ0Ngw2TDYuNExunNs5snNu4sHFp48qG14bfxrWNGxthG1EbcRtJG7c27mxkbdzbKNgo2ajYeLDxaOPJxrONFxuvNjo2ejbebLzbGNmY2Piw8Wnjy8a3jZWNHxu/NrY2dra/gJ09OwI7Qjv7dkR2xHYkdqR2ZHbkdg7sKOwo7RzaObJzbEdnx2DHZMdi58TOqZ0zO+d2Luxc2rmy47Xjt3Nt58ZO2E7UTtxO0s6tnTs7WTv3dgp2SnYqdh7sPNp5svNs58XOq52OnZ6dNzvvdkZ2JnY+7Hza+bLzbWdl58fOr52tnZ39L+Bgz4HAgdDBvgORA7EDiQOpA5kDuYMDBwoHSgeHDo4cHDvQOTA4MDmwODhxcOrgzMG5gwsHlw6uHHgd+B1cO7hxEHYQdRB3kHRw6+DOQdbBvYOCg5KDioMHB48Onhw8O3hx8Oqg46Dn4M3Bu4ORg4mDDwefDr4cfDtYOfhx8Otg62Dn+As42XMicCJ0su9E5ETsROJE6kTmRO7kwInCidLJoZMjJ8dOdE4MTkxOLE5OnJw6OXNy7uTCyaWTKydeJ34n105unISdRJ3EnSSd3Dq5c5J1cu+k4KTkpOLkwcmjkycnz05enLw66TjpOXlz8u5k5GTi5MPJp5MvJ99OVk5+nPw62TrZOf8CLvZcCFwIXey7ELkQu5C4kLqQuZC7OHChcKF0cejiyMWxC50LgwuTC4uLExenLs5cnLu4cHHp4sqF14XfxbWLGxdhF1EXcRdJF7cu7lxkXdy7KLgouai4eHDx6OLJxbOLFxevLjouei7eXLy7GLmYuPhw8eniy8W3i5WLHxe/LrYudq6/gJs9NwI3Qjf7bkRuxG4kbqRuZG7kbg7cKNwo3Ry6OXJz7EbnxuDG5Mbi5sTNqZszN+duLtxcurly43Xjd3Pt5sZN2E3UTdxN0s2tmzs3WTf3bgpuSm4qbh7cPLp5cvPs5sXNq5uOm56bNzfvbkZuJm4+3Hy6+XLz7Wbl5sfNr5utm537L+Bhz4PAg9DDvgeRB7EHiQepB5kHuYcDDwoPSg+HHo48HHvQeTB4MHmweDjxcOrhzMO5hwsPlx6uPHg9+D1ce7jxEPYQ9RD3kPRw6+HOQ9bDvYeCh5KHiocHD48enjw8e3jx8Oqh46Hn4c3Du4eRh4mHDw+fHr48fHtYefjx8Oth62Hn+Qv42PMh8CH0se9D5EPsQ+JD6kPmQ+7jwIfCh9LHoY8jH8c+dD4MPkw+LD5OfJz6OPNx7uPCx6WPKx9eH34f1z5ufIR9RH3EfSR93Pq485H1ce+j4KPko+Ljwcejjycfzz5efLz66Pjo+Xjz8e5j5GPi48PHp48vH98+Vj5+fPz62PrY+f4CAfYCCAIIA+wHEAUQB5AEkAaQBZAHOAigCKAMcBjgKMBxAF0AQwBTAEuAkwCnAc4CnAe4CHAZ4CqAN4A/wHWAmwDhANEA8QDJALcB7gJkA9wHKAQoBagEeAjwGOApwHOAlwCvAToBegHeArwHGAWYBPgI8BngK8B3gFWAnwC/AbYBdoG/QJC9IIIgwiD7QURBxEEkQaRBZEHkQQ6CKIIogxwGOQpyHEQXxBDEFMQS5CTIaZCzIOdBLoJcBrkK4g3iD3Id5CZIOEg0SDxIMshtkLsg2SD3QQpBSkEqQR6CPAZ5CvIc5CXIa5BOkF6QtyDvQUZBJkE+gnwG+QryHWQV5CfIb5BtkF3wLxBiL4QghDDEfghRCHEISQhpCFkIeYiDEIoQyhCHIY5CHIfQhTCEMIWwhDgJcRriLMR5iIsQlyGuQnhD+ENch7gJEQ4RDREPkQxxG+IuRDbEfYhCiFKISoiHEI8hnkI8h3gJ8RqiE6IX4i3Ee4hRiEmIjxCfIb5CfIdYhfgJ8RtiG2IX+gtE2IsgiCCMsB9BFEEcQRJBGkEWQR7hIIIigjLCYYSjCMcRdBEMEUwRLBFOIpxGOItwHuEiwmWEqwjeCP4I1xFuIoQjRCPEIyQj3Ea4i5CNcB+hEKEUoRLhIcJjhKcIzxFeIrxG6EToRXiL8B5hFGES4SPCZ4SvCN8RVhF+IvxG2EbYRf4CMfZiCGIIY+zHEMUQx5DEkMaQxZDHOIihiKGMcRjjKMZxDF0MQwxTDEuMkxinMc5inMe4iHEZ4yqGN4Y/xnWMmxjhGNEY8RjJGLcx7mJkY9zHKMQoxajEeIjxGOMpxnOMlxivMToxejHeYrzHGMWYxPiI8RnjK8Z3jFWMnxi/MbYxdrG/QIK9BIIEwgT7CUQJxAkkCaQJZAnkCQ4SKBIoExwmOEpwnECXwJDAlMCS4CTBaYKzBOcJLhJcJrhK4E3gT3Cd4CZBOEE0QTxBMsFtgrsE2QT3CQoJSgkqCR4SPCZ4SvCc4CXBa4JOgl6CtwTvCUYJJgk+Enwm+ErwnWCV4CfBb4Jtgl3iL5BiL4UghTDFfgpRCnEKSQppClkKeYqDFIoUyhSHKY5SHKfQpTCkMKWwpDhJcZriLMV5iosUlymuUnhT+FNcp7hJEU4RTRFPkUxxm+IuRTbFfYpCilKKSoqHFI8pnlI8p3hJ8Zqik6KX4i3Fe4pRikmKjxSfKb5SfKdYpfhJ8Ztim2KX+guk2UsjSCNMs59GlEacRpJGmkaWRp7mII0ijTLNYZqjNMdpdGkMaUxpLGlO0pymOUtznuYizWWaqzTeNP4012lu0oTTRNPE0yTT3Ka5S5NNc5+mkKaUppLmIc1jmqc0z2le0rym6aTppXlL855mlGaS5iPNZ5qvNN9pVml+0vym2abZpf8CGfYyCDIIM+xnEGUQZ5BkkGaQZZBnOMigyKDMcJjhKMNxBl0GQwZTBkuGkwynGc4ynGe4yHCZ4SqDN4M/w3WGmwzhDNEM8QzJDLcZ7jJkM9xnKGQoZahkeMjwmOEpw3OGlwyvGToZehneMrxnGGWYZPjI8JnhK8N3hlWGnwy/GbYZdpm/QI69HIIcwhz7OUQ5xDkkOaQ5ZDnkOQ5yKHIocxzmOMpxnEOXw5DDlMOS4yTHaY6zHOc5LnJc5rjK4c3hz3Gd4yZHOEc0RzxHMsdtjrsc2Rz3OQo5SjkqOR5yPOZ4yvGc4yXHa45Ojl6OtxzvOUY5Jjk+cnzm+MrxnWOV4yfHb45tjl3uL5BnL48gjzDPfh5RHnEeSR5pHlkeeZ6DPIo8yjyHeY7yHOfR5THkMeWx5DnJc5rnLM95nos8l3mu8njz+PNc57nJE84TzRPPk8xzm+cuTzbPfZ5CnlKeSp6HPI95nvI853nJ85qnk6eX5y3Pe55Rnkmejzyfeb7yfOdZ5fnJ85tnm2eX/wsU2SsiKCIssl9EVERcRFJEWkRWRF7koIiiiLLIYZGjIsdFdEUMRUxFLEVOipwWOStyXuSiyGWRqyLeIv4i10VuioSLRIvEiySL3Ba5K5Itcl+kUKRUpFLkochjkaciz0VeirwW6RTpFXkr8l5kVGRS5KPIZ5GvIt9FVkV+ivwW2RbZFf8CZfbKCMoIy+yXEZURl5GUkZaRlZGXOSijKKMsc1jmqMxxGV0ZQxlTGUuZkzKnZc7KnJe5KHNZ5qqMt4y/zHWZmzLhMtEy8TLJMrdl7spky9yXKZQplamUeSjzWOapzHOZlzKvZTplemXeyryXGZWZlPko81nmq8x3mVWZnzK/ZbZlduW/QJW9KoIqwir7VURVxFUkVaRVZFXkVQ6qKKooqxxWOapyXEVXxVDFVMVS5aTKaZWzKudVLqpcVrmq4q3ir3Jd5aZKuEq0SrxKssptlbsq2Sr3VQpVSlUqVR6qPFZ5qvJc5aXKa5VOlV6VtyrvVUZVJlU+qnxW+aryXWVV5afKb5VtlV31L1Bjr4aghrDGfg1RDXENSQ1pDVkNeY2DGooayhqHNY5qHNfQ1TDUMNWw1DipcVrjrMZ5jYsalzWuanhr+Gtc17ipEa4RrRGvkaxxW+OuRrbGfY1CjVKNSo2HGo81nmo813ip8VqjU6NX463Ge41RjUmNjxqfNb5qfNdY1fip8VtjW2NX+wvU2asjqCOss19HVEdcR1JHWkdWR17noI6ijrLOYZ2jOsd1dHUMdUx1LHVO6pzWOatzXueizmWdqzreOv4613Vu6oTrROvE6yTr3Na5q5Otc1+nUKdUp1Lnoc5jnac6z3Ve6rzW6dTp1Xmr815nVGdS56POZ52vOt91VnV+6vzW2dbZ1f8CDfYaCBoIG+w3EDUQN5A0kDaQNZA3OGigaKBscNjgqMFxA10DQwNTA0uDkwanDc4anDe4aHDZ4KqBt4G/wXWDmwbhBtEG8QbJBrcN7hpkG9w3KDQoNag0eGjw2OCpwXODlwavDToNeg3eGrw3GDWYNPho8Nngq8F3g1WDnwa/DbYNdo2/QJO9JoImwib7TURNxE0kTaRNZE3kTQ6aKJoomxw2OWpy3ETXxNDE1MTS5KTJaZOzJudNLppcNrlq4m3ib3Ld5KZJuEm0SbxJssltk7sm2Sb3TQpNSk0qTR6aPDZ5avLc5KXJa5NOk16TtybvTUZNJk0+mnw2+Wry3WTV5KfJb5Ntk13zL9Bir4WghbDFfgtRC3ELSQtpC1kLeYuDFooWyhaHLY5aHLfQtTC0MLWwtDhpcdrirMV5i4sWly2uWnhb+Ftct7hpEW4RbRFvkWxx2+KuRbbFfYtCi1KLSouHFo8tnlo8t3hp8dqi06LX4q3Fe4tRi0mLjxafLb5afLdYtfhp8dti22LX+gu02WsjaCNss99G1EbcRtJG2kbWRt7moI2ijbLNYZujNsdtdG0MbUxtLG1O2py2OWtz3uaizWWbqzbeNv42121u2oTbRNvE2yTb3La5a5Ntc9+m0KbUptLmoc1jm6c2z21e2ry26bTptXlr895m1GbS5qPNZ5uvNt9tVm1+2vy22bbZtf8CXfa6CLoIu+x3EXURd5F0kXaRdZF3Oeii6KLsctjlqMtxF10XQxdTF0uXky6nXc66nHe56HLZ5aqLt4u/y3WXmy7hLtEu8S7JLrdd7rpku9x3KXQpdal0eejy2OWpy3OXly6vXTpdel3eurx3GXWZdPno8tnlq8t3l1WXny6/XbZddt2/QJ+9PoI+wj77fUR9xH0kfaR9ZH3kfQ76KPoo+xz2Oepz3EfXx9DH1MfS56TPaZ+zPud9Lvpc9rnq4+3j73Pd56ZPuE+0T7xPss9tn7s+2T73fQp9Sn0qfR76PPZ56vPc56XPa59On16ftz7vfUZ9Jn0++nz2+erz3WfV56fPb59tn13/LzBgb4BggHDA/gDRAPEAyQDpANkA+YCDAYoBygGHA44GHA/QDTAMMA2wDDgZcDrgbMD5gIsBlwOuBngH+AdcD7gZEB4QHRAfkBxwO+BuQHbA/YDCgNKAyoCHAY8DngY8D3gZ8DqgM6A34G3A+4DRgMmAjwGfA74GfA9YDfgZ8DtgO2A3+AsM2RsiGCIcsj9ENEQ8RDJEOkQ2RD7kYIhiiHLI4ZCjIcdDdEMMQ0xDLENOhpwOORtyPuRiyOWQqyHeIf4h10NuhoSHRIfEhySH3A65G5Idcj+kMKQ0pDLkYcjjkKchz0NehrwO6QzpDXkb8j5kNGQy5GPI55CvId9DVkN+hvwO2Q7ZDf8CY/bGCMYIx+yPEY0Rj5GMkY6RjZGPORijGKMcczjmaMzxGN0YwxjTGMuYkzGnY87GnI+5GHM55mqMd4x/zPWYmzHhMdEx8THJMbdj7sZkx9yPKYwpjamMeRjzOOZpzPOYlzGvYzpjemPexryPGY2ZjPkY8znma8z3mNWYnzG/Y7ZjduO/wJS9KYIpwin7U0RTxFMkU6RTZFPkUw6mKKYopxxOOZpyPEU3xTDFNMUy5WTK6ZSzKedTLqZcTrma4p3in3I95WZKeEp0SnxKcsrtlLsp2Sn3UwpTSlMqUx6mPE55mvI85WXK65TOlN6UtynvU0ZTJlM+pnxO+ZryPWU15WfK75TtlN30LzBjb4ZghnDG/gzRDPEMyQzpDNkM+YyDGYoZyhmHM45mHM/QzTDMMM2wzDiZcTrjbMb5jIsZlzOuZnhn+Gdcz7iZEZ4RnRGfkZxxO+NuRnbG/YzCjNKMyoyHGY8znmY8z3iZ8TqjM6M3423G+4zRjMmMjxmfM75mfM9YzfiZ8TtjO2M3+wvM2ZsjmCOcsz9HNEc8RzJHOkc2Rz7nYI5ijnLO4ZyjOcdzdHMMc0xzLHNO5pzOOZtzPudizuWcqzneOf4513Nu5oTnROfE5yTn3M65m5Odcz+nMKc0pzLnYc7jnKc5z3Ne5rzO6czpzXmb8z5nNGcy52PO55yvOd9zVnN+5vzO2c7Zzf8CC/YWCBYIF+wvEC0QL5AskC6QLZAvOFigWKBccLjgaMHxAt0CwwLTAsuCkwWnC84WnC+4WHC54GqBd4F/wfWCmwXhBdEF8QXJBbcL7hZkF9wvKCwoLagseFjwuOBpwfOClwWvCzoLegveFrwvGC2YLPhY8Lnga8H3gtWCnwW/C7YLdou/wJK9JYIlwiX7S0RLxEskS6RLZEvkSw6WKJYolxwuOVpyvES3xLDEtMSy5GTJ6ZKzJedLLpZcLrla4l3iX3K95GZJeEl0SXxJcsntkrsl2SX3SwpLSksqSx6WPC55WvK85GXJ65LOkt6StyXvS0ZLJks+lnwu+VryvWS15GfJ75Ltkt3yL7Bmb41gjXDN/hrRGvEayRrpGtka+ZqDNYo1yjWHa47WHK/RrTGsMa2xrDlZc7rmbM35mos1l2uu1njX+Ndcr7lZE14TXRNfk1xzu+ZuTXbN/ZrCmtKaypqHNY9rntY8r3lZ87qms6a35m3N+5rRmsmajzWfa77WfK9ZrflZ87tmu2a3/gts2Nsg2CDcsL9BtEG8QbJBukG2Qb7hYINig3LD4YajDccbdBsMG0wbLBtONpxuONtwvuFiw+WGqw3eDf4N1xtuNoQ3RDfENyQ33G6425DdcL+hsKG0obLhYcPjhqcNzxteNrxu6GzobXjb8L5htGGy4WPD54avDd8bVht+Nvxu2G7Ybfgf1fn9D74NmNoAAAAASUVORK5CYII=", "base64");
  await page.getByRole("link", { name: "Media" }).click();
  check(await page.getByRole("heading", { name: "Media" }).isVisible(), "media page");
  await page.locator("input[type=file]").setInputFiles({ name: "Studio photo.png", mimeType: "image/png", buffer: png });
  await page.getByRole("button", { name: "Upload", exact: true }).click();
  check(await page.getByText("Uploaded 1 file.").isVisible(), "upload works");
  check(await page.locator("img.media-full").isVisible(), "image detail page");
  await page.getByLabel("Alt text").fill("The studio at dusk");
  await page.getByRole("button", { name: "Save" }).click();
  check(await page.getByLabel("Alt text").inputValue() === "The studio at dusk", "alt text saved");
  await shot("13-media-item");
  await page.getByRole("link", { name: "All media" }).click();
  await shot("13b-media");

  // ---------------------------------------------------------------- page editor
  await page.getByRole("link", { name: "Pages" }).click();
  check(await page.getByText("Home page").isVisible(), "pages list marks the home page");
  await shot("14-pages");
  await page.getByRole("link", { name: "New page" }).click();
  await page.getByPlaceholder("Page title").fill("Our services");
  check(await page.getByLabel("Address").inputValue() === "our-services", "address follows the title");
  const ta = page.locator("textarea.md-input");
  await ta.fill("## What we do\n\nWe design ");
  await ta.press("End");
  await page.getByRole("button", { name: "Bold" }).click();
  check((await ta.inputValue()).includes("**bold text**"), "bold button inserts markup");
  await page.waitForFunction(() => document.querySelector(".md-preview strong") && document.querySelector(".md-preview h2"));
  check(await page.locator(".md-preview h2").innerText() === "What we do", "live preview updates");
  check(await page.getByText("Unsaved changes").isVisible(), "unsaved indicator");
  await ta.press("End");
  await ta.press("Enter");
  await page.locator(".md-insert summary").click();
  await page.locator(".md-insert").getByRole("button", { name: /Button/ }).click();
  check((await ta.inputValue()).includes('[button url="/contact"'), "shortcode inserted");
  await page.getByRole("button", { name: "Insert image from media" }).click();
  const pick = page.locator(".md-media-grid button").first();
  await pick.waitFor();
  await pick.click();
  check((await ta.inputValue()).includes("![The studio at dusk](/media/"), "image picked from the media library");
  await page.waitForFunction(() => document.querySelector(".md-preview img"));
  check(await page.locator(".md-preview img").evaluate((i) => i.complete && i.naturalWidth > 0), "image shows in the preview");
  await page.getByLabel("Status").selectOption("published");
  await page.getByLabel("Show in the main menu").check();
  await shot("15-editor");
  await page.getByRole("button", { name: "Create page" }).click();
  check(await page.getByText("Page published.").isVisible(), "page published");
  for (const v of ["Write", "Preview", "Split"]) {
    await page.locator(".md-tabs").getByRole("button", { name: v }).click();
    check(await page.locator(".md-tabs").getByRole("button", { name: v }).getAttribute("aria-pressed") === "true", `view: ${v}`);
  }
  const site = await ctx.newPage();
  await site.goto(base + "/our-services");
  check(await site.getByRole("heading", { name: "Our services" }).isVisible(), "page live on the site");
  check(await site.getByRole("navigation").getByRole("link", { name: "Our services" }).isVisible(), "page in the main menu");
  check(await site.locator("article img").evaluate((i) => i.complete && i.naturalWidth > 0), "image loads on the site");
  await site.screenshot({ path: path.join(outDir, "16-site-page.png"), fullPage: true });
  await site.emulateMedia({ colorScheme: "dark" });
  await site.screenshot({ path: path.join(outDir, "16b-site-page-dark.png"), fullPage: true });
  await site.setViewportSize({ width: 390, height: 844 });
  await site.emulateMedia({ colorScheme: "light" });
  check(await site.evaluate(() => document.documentElement.scrollWidth - window.innerWidth) <= 0, "site page fits a phone screen");
  await site.screenshot({ path: path.join(outDir, "16c-site-page-phone.png"), fullPage: true });
  await site.goto(base + "/nope");
  check(await site.getByRole("heading", { name: "Page not found" }).isVisible(), "themed 404");
  await site.close();

  // ---------------------------------------------------------------- menus, themes, people
  await page.getByRole("link", { name: "Menus" }).click();
  check(await page.locator(".menu-row").count() === 3, "three items in the main menu");
  await page.getByRole("button", { name: "Move “Our services” up" }).click();
  check((await page.locator(".menu-row strong").nth(1).innerText()) === "Our services", "moved up");
  await shot("17-menus");

  await page.getByRole("link", { name: "Themes" }).click();
  await shot("18-themes");
  await page.getByRole("link", { name: "Customise" }).click();
  await page.getByLabel("Accent colour").fill("#0f766e");
  await page.getByLabel("Text font").selectOption("serif");
  await page.getByRole("button", { name: "Save", exact: true }).click();
  check(await page.getByText("Saved.").isVisible(), "theme settings saved");
  await shot("18b-theme-settings");

  await page.getByRole("link", { name: "People" }).click();
  await page.getByRole("link", { name: "Add person" }).click();
  await page.getByLabel("Username").fill("alice");
  await page.getByLabel("Name (optional)").fill("Alice");
  await page.locator(".choice", { hasText: "Editor" }).first().click();
  await page.getByRole("button", { name: "Add person" }).click();
  check(await page.getByLabel("One-time password").isVisible(), "one-time password shown");
  await shot("19-person-added");
  await page.getByRole("link", { name: "Done" }).click();
  await shot("19b-person");

  // ---------------------------------------------------------------- 2-step login
  await page.goto(base + "/admin/account/2fa");
  check(await page.locator("svg.wc-qr").isVisible(), "QR code shown");
  await shot("20-2fa-setup");

  // dark mode and phone width
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto(base + "/admin");
  await shot("10-dashboard-dark");
  await page.goto(base + "/admin/pages/new");
  await shot("10b-editor-dark");
  await page.emulateMedia({ colorScheme: "light" });
  for (const [name, url] of [["dashboard", "/admin"], ["settings", "/admin/settings"], ["account", "/admin/account"], ["pages", "/admin/pages"],
                             ["editor", "/admin/pages/new"], ["media", "/admin/media"], ["menus", "/admin/menus"], ["themes", "/admin/themes"], ["people", "/admin/users"]]) {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(base + url);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check(overflow <= 0, `${name} fits a phone screen (overflow ${overflow}px)`);
    if (name === "dashboard") await shot("11-dashboard-phone");
    if (name === "editor") await shot("11b-editor-phone");
  }
  const login = await (await browser.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  await login.goto(base + "/admin/login");
  check(await login.evaluate(() => document.documentElement.scrollWidth - window.innerWidth) <= 0, "sign-in page fits a phone screen");
  await login.screenshot({ path: path.join(outDir, "12-login-phone.png"), fullPage: true });

  check(problems.length === 0, "no console errors or CSP violations" + (problems.length ? ": " + problems.join(" | ") : ""));
  await browser.close();
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
