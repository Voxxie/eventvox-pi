// Onderhoud op het scherm (de agent zet dit met Runtime.evaluate): tijdens het bijwerken en vlak voor een herstart.
// window.__evxMaintenance(tekst) toont het, window.__evxMaintenance(null) haalt het weg. Zelfde stijl als het
// opstartscherm (splash.py): donker, het EventVOX-logo, een schuivend balkje dat laat zien dat hij bezig is. De tekst
// "Eerste zin. Rest" wordt een kop en een regel eronder, netjes over de regels verdeeld.
(function () {
    if (window.__evxMaintenance) return;
    var LOGO = '<svg viewBox="0 0 186 176" aria-hidden="true">'
        + '<defs><linearGradient id="evx-m-o" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff5a00"/>'
        + '<stop offset="1" stop-color="#ffaa00"/></linearGradient>'
        + '<linearGradient id="evx-m-p" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d4002e"/>'
        + '<stop offset="1" stop-color="#ff1a6e"/></linearGradient></defs>'
        + '<polygon points="47,3 4,115 94,172 154,132" fill="url(#evx-m-o)"/>'
        + '<polygon points="141,3 100,53 162,125 182,112" fill="url(#evx-m-p)"/></svg>';
    var CSS = '[data-evx-maintenance]{position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483646;display:flex;'
        + 'flex-direction:column;align-items:center;justify-content:center;background:#12101a;color:#fff;'
        + 'font-family:"Liberation Sans",Arial,sans-serif;text-align:center;padding:6vmin;box-sizing:border-box;cursor:none}'
        + '[data-evx-maintenance] svg{width:16vmin;height:auto;margin-bottom:5vmin}'
        + '[data-evx-maintenance] .evx-m-label{color:#ff6a00;font-size:2.6vmin;font-weight:700;letter-spacing:.35em;'
        + 'text-transform:uppercase;margin-bottom:2.2vmin}'
        + '[data-evx-maintenance] .evx-m-title{font-size:5.4vmin;font-weight:700;line-height:1.2;max-width:80vw;text-wrap:balance}'
        + '[data-evx-maintenance] .evx-m-text{font-size:3.2vmin;line-height:1.4;color:#c9c4d3;max-width:70vw;margin-top:1.6vmin;'
        + 'text-wrap:balance}'
        + '[data-evx-maintenance] .evx-m-bar{position:relative;overflow:hidden;width:34vmin;height:.7vmin;margin-top:6vmin;'
        + 'border-radius:.35vmin;background:#3a3444}'
        + '[data-evx-maintenance] .evx-m-bar::after{content:"";position:absolute;top:0;bottom:0;width:30%;border-radius:inherit;'
        + 'background:#ff6a00;animation:evx-m-slide 1.6s ease-in-out infinite alternate}'
        + '@keyframes evx-m-slide{from{left:0}to{left:70%}}';
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
            document.documentElement.appendChild(box);
        }
        var cut = text.indexOf('. ');
        var head = cut > 0 ? text.slice(0, cut) : text.replace(/\.$/, '');
        var rest = cut > 0 ? text.slice(cut + 2) : '';
        box.innerHTML = '<style>' + CSS + '</style>' + LOGO
            + '<div class="evx-m-label">Onderhoud</div><div class="evx-m-title"></div><div class="evx-m-text"></div>'
            + '<div class="evx-m-bar"></div>';
        box.querySelector('.evx-m-title').textContent = head;
        box.querySelector('.evx-m-text').textContent = rest;
        if (!rest) box.removeChild(box.querySelector('.evx-m-text'));
    };
})();
