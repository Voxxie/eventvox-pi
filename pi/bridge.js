// window.WebKiosk voor de EventVOX-scanterminal op een Raspberry Pi (EventVOX-Pi). Zelfde koppeling als de kiosk-app
// EventVOX-Webkiosk op een Zebra (Voxxie/eventvox-kioskapp), zodat EventVOX de Pi op dezelfde manier ziet en bedient.
// De agent (agent.py) zet dit script via de debugpoort van Chromium in elke pagina, vóór de scripts van de pagina, en
// geeft zijn staat door met window.__evxPiState(staat). Wat de pagina vraagt gaat naar de agent via window.__evxPi(json).
// Alleen op de pagina's die de agent kiest (de scanterminal); een gewone browser merkt niets.
(function () {
    if (window.WebKiosk) return;
    var state = __EVX_PI_STATE__;
    var sentLog = null;
    var lastWifi = null;
    function send(message) {
        try { window.__evxPi(JSON.stringify(message)); } catch (e) { /* agent (nog) niet verbonden */ }
    }
    function wifiEvent() {
        var w = state && state.status ? state.status.wifi || null : null;
        var key = JSON.stringify(w);
        if (key === lastWifi) return;
        lastWifi = key;
        if (!w) return;
        try { window.dispatchEvent(new CustomEvent('webkiosk-wifi', { detail: w })); } catch (e) { /* oud */ }
        if (typeof window.onWebKioskWifi === 'function') try { window.onWebKioskWifi(w); } catch (e) { /* pagina */ }
    }
    // Wanneer er voor het laatst gescand of getikt is: 's nachts herladen en bijwerken pas na 5 minuten rust
    var lastInput = Date.now();
    var touched = function () { lastInput = Date.now(); };
    window.addEventListener('keydown', touched, true);
    window.addEventListener('pointerdown', touched, true);
    window.__evxPiIdleSeconds = function () { return Math.round((Date.now() - lastInput) / 1000); };
    window.__evxPiState = function (s) {
        state = s;
        wifiEvent();
    };
    window.WebKiosk = {
        nfcAvailable: function () { return false; },
        nfcEnabled: function () { return false; },
        getSerial: function () { return state.serial || ''; },
        getDeviceInfo: function () { return JSON.stringify(state.device || {}); },
        vibrate: function () { return false; },
        /** De staat voor de heartbeat; het logboek één keer per diagnose */
        getStatus: function () {
            var s = {};
            var src = state.status || {};
            for (var k in src) if (Object.prototype.hasOwnProperty.call(src, k)) s[k] = src[k];
            if (state.log && state.log_id !== sentLog) {
                s.log = state.log;
                sentLog = state.log_id;
                send({ type: 'logSent', id: state.log_id });
            }
            return JSON.stringify(s);
        },
        /** Alleen via wifi; met een kabel null (de terminal toont dan geen wifi-balkjes) */
        getWifi: function () { return JSON.stringify(state.status && state.status.wifi ? state.status.wifi : null); },
        requestDiagnostics: function () { send({ type: 'diagnostics' }); },
        command: function (json) { send({ type: 'command', value: String(json) }); },
        applySettings: function (json) { send({ type: 'settings', value: String(json) }); },
        setAdminKey: function () { /* een Pi heeft geen beheerscherm */ },
    };
    wifiEvent();
    send({ type: 'hello' });
})();
