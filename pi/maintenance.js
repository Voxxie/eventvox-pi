// Onderhoud op het scherm (de agent zet dit met Runtime.evaluate): tijdens het bijwerken en vlak voor een herstart.
// window.__evxMaintenance(tekst) toont het, window.__evxMaintenance(null) haalt het weg.
(function () {
    if (window.__evxMaintenance) return;
    var box = null;
    window.__evxMaintenance = function (text) {
        if (!text) {
            if (box && box.parentNode) box.parentNode.removeChild(box);
            box = null;
            return;
        }
        if (!box) {
            box = document.createElement('div');
            box.setAttribute('data-evx-maintenance', '');
            box.setAttribute('style', 'position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483646;display:flex;flex-direction:column;'
                + 'align-items:center;justify-content:center;background:#5e2572;color:#fff;font:600 5vmin sans-serif;text-align:center;padding:5vmin');
            document.documentElement.appendChild(box);
        }
        box.textContent = '';
        var title = document.createElement('div');
        title.setAttribute('style', 'font-size:9vmin;margin-bottom:3vmin');
        title.textContent = 'Onderhoud';
        var body = document.createElement('div');
        body.textContent = text;
        box.appendChild(title);
        box.appendChild(body);
    };
})();
