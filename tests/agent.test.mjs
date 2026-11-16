// De agent (pi/agent.py) tegen een echte Chromium met debugpoort, zoals op de Pi:
// window.WebKiosk alleen op de scanterminal, de staat in getStatus(), opdrachten één keer per id (herstarten en
// bijwerken als proef), instellingen per versie, diagnose één keer, Zoek mij en een gevraagde browserherstart.
//   node --test tests/agent.test.mjs                    (Playwright met Chromium, Python 3)
//   FRONTEND=/pad/naar/eventvox-frontend node --test …  ook tegen de echte scanterminal van EventVOX
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync } from 'node:fs';
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
    agent = spawn('python3', [AGENT], {
        env: { ...process.env, EVX_PI_CDP: `http://127.0.0.1:${PORT}`, EVX_PI_STATE: stateDir, EVX_PI_DRYRUN: '1', EVX_PI_TICK: '0.3',
            // Wifi: wifi.py zonder sudo, met een nagebootste nmcli
            EVX_PI_WIFI: fileURLToPath(new URL('../pi/wifi.py', import.meta.url)), EVX_PI_SSH: fileURLToPath(new URL('../pi/ssh.py', import.meta.url)), EVX_PI_SSH_HOME: join(stateDir, 'home'), NMCLI: fileURLToPath(new URL('./fake-nmcli', import.meta.url)), FAKE_NM: stateDir,
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
    await page.waitForFunction(() => typeof window.WebKiosk?.getStatus === 'function', null, { timeout: 8000 });
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
    await wait(1500);
    assert.deepEqual(readFileSync(join(stateDir, 'dryrun-actions'), 'utf8').trim().split('\n'), ['reboot', 'update']);
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
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 9, command: 'locate' })));
    await page.getByText('Hier ben ik!').waitFor({ timeout: 8000 });
    await page.keyboard.press('a');
    await page.getByText('Hier ben ik!').waitFor({ state: 'detached' });
    await page.evaluate(() => { window.__before = 1; });
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 10, command: 'reload' })));
    await until(() => page.evaluate(() => window.__before === undefined).catch(() => false));
    await page.close();
});

test('the real scanterminal of EventVOX hands the Pi\'s state and a command over (FRONTEND)', { skip: !process.env.FRONTEND && 'FRONTEND niet gezet' }, async () => {
    const { startFrontend } = await import(join(process.env.FRONTEND, 'tests/browser/harness.mjs'));
    const frontend = await startFrontend();
    const beats = [];
    let command = { id: 11, command: 'update' };
    const context = await browser.newContext();
    await context.addInitScript(() => {
        localStorage.setItem('eventvox.terminal.token', 'terminal-token');
    });
    const T = 'dddddddd-1111-4111-8111-111111111111';
    const CP = 'dddddddd-3333-4333-8333-333333333333';
    await context.route(/^https:\/\/api\.eventvox\.nl\//, async (route) => {
        const url = new URL(route.request().url());
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
        await until(() => beats.some((b) => b.kiosk_status?.command_done === 11), 15000);
        assert.ok(beats.some((b) => b.kiosk_status?.app === 'pi' && b.kiosk_status?.pi), 'no Pi state in the heartbeat');
        assert.equal(command, null, 'the command was not reported done');
        assert.ok(readFileSync(join(stateDir, 'dryrun-actions'), 'utf8').includes('update'));
    } finally {
        await context.close();
        frontend.stop();
    }
});

test('a restart asked by EventVOX closes Chromium (kiosk.sh starts it again)', async () => {
    const page = await terminalPage();
    await page.evaluate(() => window.WebKiosk.command(JSON.stringify({ id: 20, command: 'restart' })));
    await until(() => !browser.isConnected(), 8000);
    assert.ok(existsSync(join(stateDir, 'restart-requested')), 'not marked as asked (would count as a crash)');
    assert.match(agentOut, /Browser herstarten: opdracht uit EventVOX/);
});
