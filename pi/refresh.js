// Scherm opfrissen op een Pi (opdracht refresh_screen uit EventVOX): tegen beeldretentie ("ingebrand" beeld) op een
// LCD-monitor. Het hele scherm wisselt elke seconde tussen wit, zwart, rood, groen en blauw, hoogstens 3 uur; een tik,
// toets of NFC-kaart stopt het (die gaat dan niet naar de scanterminal). De agent zet dit met Runtime.evaluate in de pagina.
(function () {
    if (window.__evxRefresh) return;
    var colors = ['#ffffff', '#000000', '#ff0000', '#00ff00', '#0000ff'];
    var until = Date.now() + 3 * 60 * 60 * 1000;
    var box = document.createElement('div');
    box.setAttribute('data-evx-refresh', '');
    box.setAttribute('style', 'position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483647;background:#fff;cursor:none');
    document.documentElement.appendChild(box);
    var n = 0;
    var timer = setInterval(function () {
        if (Date.now() >= until) return stop();
        box.style.background = colors[++n % colors.length];
    }, 1000);
    function stop(event) {
        if (event) { event.preventDefault(); event.stopImmediatePropagation(); }
        clearInterval(timer);
        window.removeEventListener('keydown', stop, true);
        window.removeEventListener('pointerdown', stop, true);
        if (box.parentNode) box.parentNode.removeChild(box);
        window.__evxRefresh = null;
    }
    window.addEventListener('keydown', stop, true);
    window.addEventListener('pointerdown', stop, true);
    window.__evxRefresh = { stop: stop };
})();
