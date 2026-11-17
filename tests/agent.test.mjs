// De agent (pi/agent.py) tegen een echte Chromium met debugpoort, zoals op de Pi:
// window.WebKiosk alleen op de scanterminal, de staat in getStatus(), opdrachten één keer per id (herstarten en
// bijwerken als proef), instellingen per versie, diagnose één keer, Zoek mij en een gevraagde browserherstart.
//   node --test tests/agent.test.mjs                    (Playwright met Chromium, Python 3)
//   FRONTEND=/pad/naar/eventvox-frontend node --test …  ook tegen de echte scanterminal van EventVOX
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const { chromium } = createRequire(import.meta.url)('playwright');
const AGENT = fileURLToPath(new URL('../pi/agent.py', import.meta.url));
const PORT = 9300 + Math.floor(Math.random() * 500);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 8000) {
    const end = Date.now() + ms;
    for (;;) {
        const v = await fn();
        if (v) return v;
        if (Date.now() > end) throw new Error('timeout: ' + fn);
        await wait(100);
    }
}

let browser, agent, stateDir, server, base, agentOut = '';
before(async () => {
    // Een kleine "scanterminal" en een andere pagina op een eigen poort
    server = createServer((req, res) => {
        res.setHeader('content-type', 'text/html');
        res.end(req.url.startsWith('/scanterminal') ? '<!doctype html><title>terminal</title><p>scanterminal</p>' : '<!doctype html><p>iets anders</p>');
    });
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ args: [`--remote-debugging-port=${PORT}`, '--autoplay-policy=no-user-gesture-required'] });
    stateDir = mkdtempSync(join(tmpdir(), 'evx-pi-'));
    mkdirSync(join(stateDir, 'home'));
    mkdirSync(join(stateDir, 'rpic'));
    mkdirSync(join(stateDir, 'units'));
    agent = spawn('python3', [AGENT], {
        env: { ...process.env, EVX_PI_CDP: `http://127.0.0.1:${PORT}`, EVX_PI_STATE: stateDir, EVX_PI_DRYRUN: '1', EVX_PI_TICK: '0.3',
            // Wifi: wifi.py zonder sudo, met een nagebootste nmcli
            EVX_PI_WIFI: fileURLToPath(new URL('../pi/wifi.py', import.meta.url)), EVX_PI_SSH: fileURLToPath(new URL('../pi/ssh.py', import.meta.url)), EVX_PI_SSH_HOME: join(stateDir, 'home'),
            // NFC: nummers uit een bestand in plaats van een lezer; onderhoud: een bestand in plaats van systemctl
            EVX_PI_NFC_FAKE: join(stateDir, 'nfc'), EVX_PI_SYSTEMCTL: fileURLToPath(new URL('./fake-systemctl', import.meta.url)), FAKE_SYSTEMCTL: join(stateDir, 'units'), NMCLI: fileURLToPath(new URL('./fake-nmcli', import.meta.url)), FAKE_NM: stateDir,
            EVX_PI_ROOT_FAIL: join(stateDir, 'root-fail'),
            EVX_PI_RPI_CONNECT: fileURLToPath(new URL('./fake-rpi-connect', import.meta.url)), FAKE_RPIC: join(stateDir, 'rpic'),
            EVX_PI_PAGE_MATCH: '^http://127\\.0\\.0\\.1:\\d+/scanterminal' },
    });
    agent.stdout.on('data', (d) => { agentOut += d; });
    agent.stderr.on('data', (d) => { agentOut += d; });
});
after(async () => {
    agent?.kill();
    await browser?.close();
    server?.close();
});

async function terminalPage() {
    const page = await browser.newPage();
    await page.goto(`${base}/scanterminal/?serial=abc`);
    await page.waitForFunction(() => typeof window.WebKiosk?.getStatus === 'function', null, { timeout: 20000 });
    return page;
}
const status = (page) => page.evaluate(() => JSON.parse(window.WebKiosk.getStatus()));

test('window.WebKiosk on the scanterminal with the Pi\'s state; not on another page', async () => {
    const page = await terminalPage();
    const s = await status(page);
    assert.equal(s.app, 'pi');
    assert.equal(s.version, '0.0.0-dev');
    assert.equal(s.channel, 'stable');
    assert.ok(Number.isInteger(s.uptime_s));
    assert.equal(typeof s.pi, 'object');
    assert.equal(s.wifi_version, '', 'wifi_version (empty) tells EventVOX this version takes wifi networks');
    assert.equal(await page.evaluate(() => window.WebKiosk.nfcAvailable()), false);
    // getNetwork: uplink and cable as in the status (the scanterminal shows a cable icon on the cable)
    const net = JSON.parse(await page.evaluate(() => window.WebKiosk.getNetwork()));
    assert.deepEqual(Object.keys(net).sort(), ['ethernet', 'uplink']);
    assert.equal(net.uplink, s.uplink ?? null);
    // Rust sinds de laatste toets (voor 's nachts herladen)
    await page.keyboard.press('a');
    assert.ok(await page.evaluate(() => window.__evxPiIdleSeconds()) < 2);
    // After a reload it is there again, before the page's own scripts
    await page.reload();
    await page.waitForFunction(() => typeof window.WebKiosk?.command === 'function');
    const other = await browser.newPage();
    await other.goto(`${base}/elders`);
    await wait(800);
    assert.equal(await other.evaluate(() => typeof window.WebKiosk), 'undefined');
    await other.close();
    await page.close();
});

test('a command runs once per id and is reported done; reboot and update (dry run); settings once per version', async () => {
    const page = await terminalPage();
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 7, command: 'reboot' })));
    await until(async () => (await status(page)).command_done === 7);
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 7, command: 'reboot' })));
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 8, command: 'update' })));
    await until(async () => (await status(page)).command_done === 8);
    // Only EventVOX-Pi (no Linux, no reboot of the Pi): its own root action
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 9, command: 'update_app' })));
    await wait(1500);
    assert.deepEqual(readFileSync(join(stateDir, 'dryrun-actions'), 'utf8').trim().split('\n'), ['reboot', 'update', 'update-app']);
    // A half-updated Pi whose root helper does not know update-app yet: then everything (that repairs it)
    writeFileSync(join(stateDir, 'root-fail'), 'update-app\n');
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 10, command: 'update_app' })));
    await wait(1500);
    assert.deepEqual(readFileSync(join(stateDir, 'dryrun-actions'), 'utf8').trim().split('\n'), ['reboot', 'update', 'update-app', 'update-app', 'update']);
    rmSync(join(stateDir, 'root-fail'));
    // Settings: what a Pi uses; the rest (NFC, volume) is not for a Pi
    await page.evaluate(() => window.WebKiosk.applySettings(JSON.stringify({ version: 3, values: { update_channel: 'beta', volume_lock: 60, nightly_hour: 5 } })));
    await until(async () => (await status(page)).settings_version === 3);
    assert.equal((await status(page)).channel, 'beta');
    const saved = JSON.parse(readFileSync(join(stateDir, 'state.json'), 'utf8'));
    assert.deepEqual(saved.settings, { update_channel: 'beta', nightly_hour: 5 });
    await page.close();
});

test('wifi networks from EventVOX: set once per version (wifi.py with a fake nmcli), reported in the status', async () => {
    const page = await terminalPage();
    const wifi = { version: 'aaaaaaaaaaaaaaaa', networks: [{ ssid: 'EventVOX-Scan', security: 'WPA', password: 'scan-wachtwoord-1', hidden: false, priority: 50 }] };
    await page.evaluate((w) => window.WebKiosk.setWifiProfiles(JSON.stringify(w)), wifi);
    await until(async () => (await status(page)).wifi_version === 'aaaaaaaaaaaaaaaa');
    const s = await status(page);
    assert.match(s.wifi_result, /1 ingesteld \(EventVOX-Scan\)/);
    assert.doesNotMatch(JSON.stringify(s), /scan-wachtwoord/, 'the password in the status');
    assert.doesNotMatch(readFileSync(join(stateDir, 'log.txt'), 'utf8'), /scan-wachtwoord/, 'the password in the log');
    // The same version again: nothing
    const before = readFileSync(join(stateDir, 'calls'), 'utf8');
    await page.evaluate((w) => window.WebKiosk.setWifiProfiles(JSON.stringify(w)), wifi);
    await wait(800);
    assert.equal(readFileSync(join(stateDir, 'calls'), 'utf8'), before, 'applied twice');
    await page.close();
});

test('SSH keys from EventVOX: in authorized_keys once per version, reported in the status', async () => {
    const page = await terminalPage();
    assert.equal((await status(page)).ssh_version, '', 'ssh_version (empty) tells EventVOX this Pi takes SSH keys');
    const ssh = { version: 'bbbbbbbbbbbbbbbb', keys: ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFoHZFVa9sx/pABql+KY2/5u+XxycAQKk+P814wP5jo eventvox:Hans'] };
    await page.evaluate((k) => window.WebKiosk.setSshKeys(JSON.stringify(k)), ssh);
    await until(async () => (await status(page)).ssh_version === 'bbbbbbbbbbbbbbbb');
    assert.match((await status(page)).ssh_result, /1 sleutel \(Hans\)/);
    assert.match(readFileSync(join(stateDir, 'home', '.ssh', 'authorized_keys'), 'utf8'), /eventvox:Hans/);
    await page.close();
});

test('an NFC reader without keyboard mode (PC/SC): the number is typed with Enter, once while the card lies there', async () => {
    const page = await terminalPage();
    // Zoals de scanterminal: losse keydown-events op document (geen invoerveld)
    await page.evaluate(() => {
        window.__typed = [];
        let buf = '';
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { window.__typed.push(buf); buf = ''; } else if (e.key.length === 1) buf += e.key;
        });
    });
    appendFileSync(join(stateDir, 'nfc'), '04A1B2C3\n04A1B2C3\n');
    await until(() => page.evaluate(() => window.__typed.length >= 1));
    await wait(600);
    assert.deepEqual(await page.evaluate(() => window.__typed), ['04A1B2C3'], 'typed twice while the card lay there');
    await wait(1300);
    appendFileSync(join(stateDir, 'nfc'), '04A1B2C3\n');
    await until(() => page.evaluate(() => window.__typed.length === 2));
    assert.doesNotMatch(readFileSync(join(stateDir, 'log.txt'), 'utf8'), /04A1B2C3/, 'the number in the log');
    await page.close();
});

test('maintenance: on the screen while updating (the oneshot service is "activating"), gone afterwards', async () => {
    const page = await terminalPage();
    const unit = join(stateDir, 'units', 'eventvox-pi-update.service');
    writeFileSync(unit, 'activating\n');
    await page.getByText('De terminal wordt bijgewerkt').waitFor({ timeout: 8000 });
    // Also after a reload
    await page.reload();
    await page.getByText('De terminal wordt bijgewerkt').waitFor({ timeout: 8000 });
    writeFileSync(unit, 'inactive\n');
    await page.getByText('De terminal wordt bijgewerkt').waitFor({ state: 'detached', timeout: 8000 });
    // Only EventVOX-Pi: its own service, the same screen
    const app = join(stateDir, 'units', 'eventvox-pi-update-app.service');
    writeFileSync(app, 'activating\n');
    await page.getByText('De terminal wordt bijgewerkt').waitFor({ timeout: 8000 });
    writeFileSync(app, 'inactive\n');
    await page.getByText('De terminal wordt bijgewerkt').waitFor({ state: 'detached', timeout: 8000 });
    await page.close();
});

test('diagnosis: the log goes with getStatus once', async () => {
    const page = await terminalPage();
    await page.evaluate(() => window.WebKiosk.requestDiagnostics());
    const log = await until(() => page.evaluate(() => JSON.parse(window.WebKiosk.getStatus()).log));
    assert.match(log, /Diagnose gevraagd door EventVOX/);
    assert.match(log, /--- Pi:/);
    assert.equal((await status(page)).log, undefined, 'the log twice');
    await page.close();
});

test('Zoek mij: a flashing screen that a key stops; reload', async () => {
    const page = await terminalPage();
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 12, command: 'locate' })));
    await page.getByText('Hier ben ik!').waitFor({ timeout: 8000 });
    await page.keyboard.press('a');
    await page.getByText('Hier ben ik!').waitFor({ state: 'detached' });
    await page.evaluate(() => { window.__before = 1; });
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 13, command: 'reload' })));
    await until(() => page.evaluate(() => window.__before === undefined).catch(() => false));
    await page.close();
});

test('the real scanterminal of EventVOX hands the Pi\'s state and a command over (FRONTEND)', { skip: !process.env.FRONTEND && 'FRONTEND niet gezet' }, async () => {
    const { startFrontend } = await import(join(process.env.FRONTEND, 'tests/browser/harness.mjs'));
    const frontend = await startFrontend();
    const beats = [];
    const sent = [];
    let command = { id: 14, command: 'update' };
    const context = await browser.newContext();
    await context.addInitScript(() => {
        localStorage.setItem('eventvox.terminal.token', 'terminal-token');
    });
    const T = 'dddddddd-1111-4111-8111-111111111111';
    const CP = 'dddddddd-3333-4333-8333-333333333333';
    await context.route(/^https:\/\/api\.eventvox\.nl\//, async (route) => {
        const url = new URL(route.request().url());
        sent.push(`${route.request().method()} ${url.pathname} ${route.request().postData() ?? ''}`);
        if (url.pathname === '/terminal/heartbeat') {
            const body = JSON.parse(route.request().postData() || '{}');
            beats.push(body);
            if (command && body.kiosk_status?.command_done === command.id) command = null;
            return route.fulfill({ json: { terminal_uuid: 'dddddddd-2222-4222-8222-222222222222', status: 'active', heartbeat_seconds: 60,
                server_time: new Date().toISOString(), name: 'Pi bij de ingang', mode: 'kiosk', tenant_uuid: T, tenant_name: 'Stichting Testdorp',
                checkpoint: { checkpoint_uuid: CP, name: 'Hoofdingang', is_active: true, result_seconds: 4, progress_days: null },
                checkpoint_changed_at: null, checkpoints: [], message: null, message_html: null, kiosk_command: command } });
        }
        return route.fulfill({ status: 404, json: { error: 'Not found' } });
    });
    const page = await context.newPage();
    await page.goto(`${frontend.url}/scanterminal/?serial=abc`);
    try {
        await until(() => beats.some((b) => b.kiosk_status?.command_done === 14), 15000);
        assert.ok(beats.some((b) => b.kiosk_status?.app === 'pi' && b.kiosk_status?.pi), 'no Pi state in the heartbeat');
        assert.equal(command, null, 'the command was not reported done');
        assert.ok(readFileSync(join(stateDir, 'dryrun-actions'), 'utf8').includes('update'));
        // A card on a PC/SC reader: typed into the real scanterminal, which scans it
        appendFileSync(join(stateDir, 'nfc'), '04C0FFEE\n');
        await until(() => sent.some((x) => x.includes('04C0FFEE')), 10000);
    } finally {
        await context.close();
        frontend.stop();
    }
});

test('Scherm opfrissen: colours over the whole page; a key stops it and does not reach the page', async () => {
    const page = await terminalPage();
    await page.evaluate(() => { window.__keys = []; document.addEventListener('keydown', (e) => window.__keys.push(e.key)); });
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 15, command: 'refresh_screen' })));
    await page.locator('[data-evx-refresh]').waitFor({ timeout: 8000 });
    const first = await page.locator('[data-evx-refresh]').evaluate((el) => getComputedStyle(el).backgroundColor);
    await page.waitForFunction((c) => getComputedStyle(document.querySelector('[data-evx-refresh]')).backgroundColor !== c, first, { timeout: 4000 });
    await page.keyboard.press('a');
    await page.locator('[data-evx-refresh]').waitFor({ state: 'detached', timeout: 4000 });
    assert.deepEqual(await page.evaluate(() => window.__keys), [], 'the key that stopped it reached the page');
    await page.close();
});

test('Raspberry Pi Connect from EventVOX: a sign-in link in the status until approved, then signed in; sign out', async () => {
    const page = await terminalPage();
    await until(async () => (await status(page)).connect?.installed === true);
    assert.equal((await status(page)).connect.signed_in, false);
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 16, command: 'connect_signin' })));
    await until(async () => (await status(page)).connect?.verify_url === 'https://connect.raspberrypi.com/verify/ABCD-1234');
    assert.ok((await status(page)).connect.verify_until);
    writeFileSync(join(stateDir, 'rpic', 'approved'), '');
    await until(async () => (await status(page)).connect?.signed_in === true && !(await status(page)).connect.verify_url);
    assert.ok(!readFileSync(join(stateDir, 'log.txt'), 'utf8').includes('verify/'), 'the link is not in the log');
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 17, command: 'connect_signout' })));
    await until(async () => (await status(page)).connect?.signed_in === false);
    await page.close();
});

test('a restart asked by EventVOX closes Chromium (kiosk.sh starts it again)', async () => {
    const page = await terminalPage();
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 20, command: 'restart' })));
    await until(() => !browser.isConnected(), 8000);
    assert.ok(existsSync(join(stateDir, 'restart-requested')), 'not marked as asked (would count as a crash)');
    assert.match(agentOut, /Browser herstarten: opdracht uit EventVOX/);
});
