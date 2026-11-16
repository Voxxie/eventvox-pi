// Zoek mij op een Pi: 30 s een knipperend scherm en een piep over HDMI (Web Audio); een tik of toets stopt het.
// De agent zet dit met Runtime.evaluate in de pagina.
(function () {
    if (window.__evxLocate) return;
    var box = document.createElement('div');
    box.setAttribute('style', 'position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483647;display:flex;align-items:center;'
        + 'justify-content:center;font:bold 8vmin sans-serif;color:#fff;background:#5e2572;text-align:center;cursor:pointer');
    box.textContent = 'Hier ben ik! Tik of druk op een toets om te stoppen';
    document.documentElement.appendChild(box);
    var audio = null;
    try { audio = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { audio = null; }
    var n = 0;
    function beep() {
        if (!audio) return;
        try {
            var o = audio.createOscillator(), g = audio.createGain();
            o.frequency.value = 1400;
            g.gain.value = 0.6;
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + 0.5);
        } catch (e) { /* geen geluid */ }
    }
    var timer = setInterval(function () {
        n += 1;
        box.style.background = n % 2 ? '#ff6a00' : '#5e2572';
        beep();
        if (n >= 30) stop();
    }, 1000);
    beep();
    function stop(event) {
        if (event) { event.preventDefault(); event.stopPropagation(); }
        clearInterval(timer);
        if (box.parentNode) box.parentNode.removeChild(box);
        window.removeEventListener('keydown', stop, true);
        if (audio) try { audio.close(); } catch (e) { /* al dicht */ }
        window.__evxLocate = null;
    }
    box.addEventListener('pointerdown', stop, true);
    window.addEventListener('keydown', stop, true);
    window.__evxLocate = { stop: stop };
})();
