import Foundation

/// ページに読み込ませる補助スクリプトと、内蔵ウィジェットのHTML。
/// このファイルは dev/build_assets.py が自動生成します。直接は編集しないでください。
enum WebAssets {
    /// 内蔵ウィジェット用の、実在しない専用アドレス（.invalid は予約済みで、どこにもつながらない）
    static let widgetHost = "widgets.kukan.invalid"

    static let widgets: [(id: String, name: String)] = [
        (id: "clock", name: "時計"),
        (id: "timer", name: "タイマー"),
        (id: "memo", name: "メモ"),
        (id: "ambient", name: "環境音")
    ]

    static func widgetURLString(_ id: String) -> String {
        "https://" + widgetHost + "/" + id
    }

    static func widgetID(for url: URL?) -> String? {
        guard let url = url, url.host == widgetHost else { return nil }
        let id = url.lastPathComponent
        for w in widgets where w.id == id { return id }
        return nil
    }

    static func widgetName(_ id: String) -> String {
        for w in widgets where w.id == id { return w.name }
        return id
    }

    static func widgetHTML(_ id: String) -> String? {
        switch id {
        case "clock": return clockHTML
        case "timer": return timerHTML
        case "memo": return memoHTML
        case "ambient": return ambientHTML
        default: return nil
        }
    }

    static let bootstrapScript = #"""
// 空間モニター：各ページに最初に読み込ませる補助スクリプト
(function () {
  if (window.__kukan) return;
  var K = window.__kukan = {};
  var top = window === window.top;

  // ---- 入力欄にカーソルが入ったことをアプリへ知らせる ----
  // 最後にカーソルが入った入力欄を覚えておき、アプリ内キーボードの文字をそこへ入れる
  K.lastField = null;
  function fieldText(t) {
    return String(t.isContentEditable ? (t.textContent || '') : (t.value || '')).slice(0, 2000);
  }
  document.addEventListener('focusin', function (e) {
    var t = e.target; if (!t) return;
    var n = (t.tagName || '').toLowerCase();
    var ty = (t.type || '').toLowerCase();
    if (n === 'input' && /^(button|submit|checkbox|radio|range|file|color|image|reset|hidden)$/.test(ty)) return;
    if (n === 'input' || n === 'textarea' || t.isContentEditable) {
      K.lastField = t;
      var secure = ty === 'password';
      try {
        // パスワード欄の中身はアプリ側へ渡さない
        window.webkit.messageHandlers.kukanFocus.postMessage({ value: secure ? '' : fieldText(t), secure: secure });
      } catch (_) {}
    }
  }, true);

  // 覚えている入力欄がまだページ上にあるか
  K.hasField = function () {
    return !!(K.lastField && K.lastField.isConnected);
  };

  // 入力欄の中身を丸ごと置き換える（ページ側のプログラムにも変更が伝わるよう、入力イベントを出す）
  K.setFieldValue = function (text) {
    var t = K.lastField;
    if (!t || !t.isConnected) return false;
    if (t.isContentEditable) {
      t.focus();
      document.execCommand('selectAll', false, null);
      document.execCommand('insertText', false, text);
      return true;
    }
    var proto = (t.tagName || '').toLowerCase() === 'textarea' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) desc.set.call(t, text); else t.value = text;
    t.dispatchEvent(new Event('input', { bubbles: true }));
    t.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };

  // 決定（Enter）：ページがEnterキーを自分で処理しなければ、フォームを送信する
  K.submitField = function () {
    var t = K.lastField;
    if (!t || !t.isConnected) return false;
    var opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    var go = t.dispatchEvent(new KeyboardEvent('keydown', opts));
    t.dispatchEvent(new KeyboardEvent('keypress', opts));
    t.dispatchEvent(new KeyboardEvent('keyup', opts));
    if ((t.tagName || '').toLowerCase() === 'textarea' && !t.form) return true;
    if (go && t.form) {
      if (t.form.requestSubmit) t.form.requestSubmit(); else t.form.submit();
    }
    return true;
  };

  // ---- 消音（音声フォーカス用）：アプリが消した音だけを、あとで戻す ----
  K.muted = false;
  var mutedByUs = new WeakSet();
  function applyMute() {
    document.querySelectorAll('video,audio').forEach(function (m) {
      try {
        if (K.muted) { if (!m.muted) { m.muted = true; mutedByUs.add(m); } }
        else if (mutedByUs.has(m)) { m.muted = false; mutedByUs.delete(m); }
      } catch (_) {}
    });
  }
  K.setMuted = function (on) {
    K.muted = !!on;
    applyMute();
    document.querySelectorAll('iframe').forEach(function (f) {
      try { f.contentWindow.postMessage({ __kukanMuted: K.muted }, '*'); } catch (_) {}
    });
    return K.muted;
  };
  window.addEventListener('message', function (e) {
    var d = e.data;
    if (d && typeof d === 'object' && typeof d.__kukanMuted === 'boolean') K.setMuted(d.__kukanMuted);
  });
  function keepMuted(e) {
    var m = e.target;
    if (K.muted && m && typeof m.muted === 'boolean' && !m.muted) { m.muted = true; mutedByUs.add(m); }
  }
  document.addEventListener('play', keepMuted, true);
  document.addEventListener('volumechange', keepMuted, true);

  // ---- 動画をページ（＝モニター）いっぱいに広げる ----
  var STYLE_ID = 'kukan-fill-style';
  var CSS = [
    'html[data-kukan-fill-on]{overflow:hidden!important}',
    '[data-kukan-fill-anc]{transform:none!important;filter:none!important;-webkit-backdrop-filter:none!important;backdrop-filter:none!important;',
    'perspective:none!important;contain:none!important;will-change:auto!important;clip-path:none!important;-webkit-mask:none!important;mask:none!important;',
    'overflow:visible!important;opacity:1!important;z-index:2147483646!important}',
    '[data-kukan-fill]{position:fixed!important;left:0!important;top:0!important;right:0!important;bottom:0!important;',
    'width:100vw!important;height:100vh!important;min-width:0!important;min-height:0!important;max-width:none!important;max-height:none!important;',
    'margin:0!important;padding:0!important;border:0!important;border-radius:0!important;transform:none!important;',
    'z-index:2147483647!important;background:#000!important}',
    '[data-kukan-fill-mid]{position:absolute!important;left:0!important;top:0!important;width:100%!important;height:100%!important;',
    'max-width:none!important;max-height:none!important;margin:0!important;padding:0!important;transform:none!important}',
    '[data-kukan-fill] video{position:absolute!important;left:0!important;top:0!important;width:100%!important;height:100%!important;',
    'max-width:none!important;max-height:none!important;object-fit:contain!important;transform:none!important}',
    'video[data-kukan-fill]{object-fit:contain!important}',
    'iframe[data-kukan-fill]{background:#000!important}'
  ].join('');

  function area(el) {
    var r = el.getBoundingClientRect();
    if (r.width < 120 || r.height < 68) return 0;
    return r.width * r.height;
  }

  // 広げる対象：再生中の大きい動画を優先。操作ボタンを含む「入れ物」が分かればそれごと広げる。
  function pickTarget() {
    var best = null, bestScore = 0;
    document.querySelectorAll('video').forEach(function (v) {
      var a = area(v); if (!a) return;
      var s = a * (v.paused ? 1 : 4);
      if (s > bestScore) { bestScore = s; best = v; }
    });
    if (best) {
      var known = best.closest('#movie_player, .html5-video-player, .video-js, .jwplayer, .plyr, .shaka-video-container');
      if (known) return { target: known, video: best };
      var va = area(best), el = best;
      while (el.parentElement && el.parentElement !== document.body && el.parentElement !== document.documentElement) {
        var pa = area(el.parentElement);
        if (!pa || pa > va * 1.25) break;
        el = el.parentElement;
      }
      return { target: el, video: best };
    }
    var frame = null, fa = 200 * 120;
    document.querySelectorAll('iframe').forEach(function (f) {
      var a = area(f);
      if (a > fa) { fa = a; frame = f; }
    });
    return frame ? { target: frame, video: null } : null;
  }

  function clearFill() {
    document.querySelectorAll('[data-kukan-fill],[data-kukan-fill-anc],[data-kukan-fill-mid]').forEach(function (el) {
      el.removeAttribute('data-kukan-fill');
      el.removeAttribute('data-kukan-fill-anc');
      el.removeAttribute('data-kukan-fill-mid');
    });
    document.documentElement.removeAttribute('data-kukan-fill-on');
    K.fillOn = false;
  }

  K.fillOn = false;
  // 戻り値：'on'（広げた）/ 'off'（戻した）/ 'none'（動画が見つからない）
  K.fill = function (on) {
    if (!on) {
      clearFill();
      window.dispatchEvent(new Event('resize'));
      return 'off';
    }
    clearFill();
    var pick = pickTarget();
    if (!pick) return 'none';
    if (!document.getElementById(STYLE_ID)) {
      var st = document.createElement('style');
      st.id = STYLE_ID;
      st.textContent = CSS;
      (document.head || document.documentElement).appendChild(st);
    }
    var root = document.documentElement;
    pick.target.setAttribute('data-kukan-fill', '');
    for (var p = pick.target.parentElement; p && p !== root; p = p.parentElement) p.setAttribute('data-kukan-fill-anc', '');
    if (pick.video && pick.video !== pick.target) {
      for (var m = pick.video.parentElement; m && m !== pick.target; m = m.parentElement) m.setAttribute('data-kukan-fill-mid', '');
    }
    root.setAttribute('data-kukan-fill-on', '');
    K.fillOn = true;
    window.dispatchEvent(new Event('resize'));
    return 'on';
  };

  // ---- ウィジェット用：アプリのテーマ色を受け取る ----
  K.setTheme = function (bg, fg, mute, accent) {
    var s = document.documentElement.style;
    s.setProperty('--k-bg', bg); s.setProperty('--k-fg', fg);
    s.setProperty('--k-mute', mute); s.setProperty('--k-accent', accent);
    return true;
  };
  void top;
})();
"""#

    static let clockHTML = #"""
<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>時計</title>
<style>:root{--k-bg:#141d3a;--k-fg:#e9edf9;--k-mute:#95a2c6;--k-accent:#ffb454}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--k-bg);color:var(--k-fg);font-family:-apple-system,"Hiragino Sans","Yu Gothic UI",system-ui,sans-serif;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3vmin;padding:4vmin;overflow:hidden;
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
h1{margin:0;font-size:3.2vmin;font-weight:600;letter-spacing:.18em;color:var(--k-mute)}
.row{display:flex;gap:2vmin;flex-wrap:wrap;justify-content:center}
button{font:600 3.6vmin/1 inherit;color:var(--k-fg);background:transparent;border:.4vmin solid var(--k-mute);border-radius:99vmin;
  padding:2.2vmin 4vmin;min-width:16vmin;cursor:pointer}
button.on,button.primary{background:var(--k-accent);border-color:var(--k-accent);color:#1b1206}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-variant-numeric:tabular-nums}
.mute{color:var(--k-mute)}

#time{font-size:24vmin;font-weight:600;line-height:1;letter-spacing:-.02em}
#sec{font-size:9vmin;color:var(--k-accent);margin-left:1.5vmin}
#date{font-size:5vmin}
#day{width:70vw;height:1.2vmin;border-radius:1vmin;background:color-mix(in srgb,var(--k-mute) 30%,transparent);overflow:hidden}
#day i{display:block;height:100%;background:var(--k-accent);width:0}
#left{font-size:3.2vmin}
</style></head><body>
<h1>時計</h1>
<div class="mono"><span id="time">--:--</span><span id="sec">--</span></div>
<div id="date"></div>
<div id="day"><i id="bar"></i></div>
<div id="left" class="mute"></div>
<script>
var W='日月火水木金土', z=function(n){return String(n).padStart(2,'0')};
function tick(){var d=new Date();
  document.getElementById('time').textContent=z(d.getHours())+':'+z(d.getMinutes());
  document.getElementById('sec').textContent=z(d.getSeconds());
  document.getElementById('date').textContent=d.getFullYear()+'年'+(d.getMonth()+1)+'月'+d.getDate()+'日（'+W[d.getDay()]+'）';
  var s=d.getHours()*3600+d.getMinutes()*60+d.getSeconds(), r=86400-s;
  document.getElementById('bar').style.width=(s/864).toFixed(2)+'%';
  document.getElementById('left').textContent='今日の残り '+Math.floor(r/3600)+'時間'+Math.floor(r%3600/60)+'分';}
tick();setInterval(tick,1000);
</script></body></html>
"""#

    static let timerHTML = #"""
<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>タイマー</title>
<style>:root{--k-bg:#141d3a;--k-fg:#e9edf9;--k-mute:#95a2c6;--k-accent:#ffb454}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--k-bg);color:var(--k-fg);font-family:-apple-system,"Hiragino Sans","Yu Gothic UI",system-ui,sans-serif;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3vmin;padding:4vmin;overflow:hidden;
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
h1{margin:0;font-size:3.2vmin;font-weight:600;letter-spacing:.18em;color:var(--k-mute)}
.row{display:flex;gap:2vmin;flex-wrap:wrap;justify-content:center}
button{font:600 3.6vmin/1 inherit;color:var(--k-fg);background:transparent;border:.4vmin solid var(--k-mute);border-radius:99vmin;
  padding:2.2vmin 4vmin;min-width:16vmin;cursor:pointer}
button.on,button.primary{background:var(--k-accent);border-color:var(--k-accent);color:#1b1206}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-variant-numeric:tabular-nums}
.mute{color:var(--k-mute)}

#wrap{position:relative;width:46vmin;height:46vmin}
svg{width:100%;height:100%;transform:rotate(-90deg)}
circle{fill:none;stroke-width:5}
#bg{stroke:color-mix(in srgb,var(--k-mute) 30%,transparent)}
#fg{stroke:var(--k-accent);stroke-linecap:round;transition:stroke-dashoffset .3s linear}
#time{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:12vmin;font-weight:600}
body.done #time{color:var(--k-accent)}
#presets button{min-width:0;padding:1.6vmin 3vmin;font-size:3vmin}
</style></head><body>
<h1>タイマー</h1>
<div id="wrap"><svg viewBox="0 0 100 100"><circle id="bg" cx="50" cy="50" r="45"/><circle id="fg" cx="50" cy="50" r="45"/></svg>
<div id="time" class="mono">25:00</div></div>
<div class="row" id="presets"><button data-m="5">5分</button><button data-m="15">15分</button><button data-m="25" class="on">25分</button><button data-m="50">50分</button></div>
<div class="row"><button id="go" class="primary">スタート</button><button id="reset">リセット</button></div>
<script>
var total=25*60,left=total,endAt=0,timer=0,C=2*Math.PI*45,fg=document.getElementById('fg'),ac=null;
fg.style.strokeDasharray=C;
function show(){var m=Math.floor(left/60),s=Math.round(left%60);if(s===60){m++;s=0}
  document.getElementById('time').textContent=String(m).padStart(2,'0')+':'+String(s).padStart(2,'0');
  fg.style.strokeDashoffset=C*(1-left/total);}
function beep(){try{ac=ac||new (window.AudioContext||window.webkitAudioContext)();[0,.35,.7].forEach(function(t){var o=ac.createOscillator(),g=ac.createGain();
  o.frequency.value=880;g.gain.setValueAtTime(.0001,ac.currentTime+t);g.gain.exponentialRampToValueAtTime(.3,ac.currentTime+t+.02);
  g.gain.exponentialRampToValueAtTime(.0001,ac.currentTime+t+.3);o.connect(g);g.connect(ac.destination);o.start(ac.currentTime+t);o.stop(ac.currentTime+t+.32);});}catch(e){}}
function stop(){clearInterval(timer);timer=0;document.getElementById('go').textContent='スタート';}
function step(){left=Math.max(0,(endAt-Date.now())/1000);show();if(left<=0){stop();document.body.classList.add('done');beep();}}
document.getElementById('go').onclick=function(){
  try{ac=ac||new (window.AudioContext||window.webkitAudioContext)();ac.resume();}catch(e){}
  if(timer){stop();return}
  if(left<=0)left=total;document.body.classList.remove('done');
  endAt=Date.now()+left*1000;timer=setInterval(step,250);this.textContent='一時停止';};
document.getElementById('reset').onclick=function(){stop();left=total;document.body.classList.remove('done');show();};
document.querySelectorAll('#presets button').forEach(function(b){b.onclick=function(){
  document.querySelectorAll('#presets button').forEach(function(x){x.classList.remove('on')});b.classList.add('on');
  stop();total=left=(+b.dataset.m)*60;document.body.classList.remove('done');show();};});
show();
</script></body></html>
"""#

    static let memoHTML = #"""
<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>メモ</title>
<style>:root{--k-bg:#141d3a;--k-fg:#e9edf9;--k-mute:#95a2c6;--k-accent:#ffb454}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--k-bg);color:var(--k-fg);font-family:-apple-system,"Hiragino Sans","Yu Gothic UI",system-ui,sans-serif;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3vmin;padding:4vmin;overflow:hidden;
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
h1{margin:0;font-size:3.2vmin;font-weight:600;letter-spacing:.18em;color:var(--k-mute)}
.row{display:flex;gap:2vmin;flex-wrap:wrap;justify-content:center}
button{font:600 3.6vmin/1 inherit;color:var(--k-fg);background:transparent;border:.4vmin solid var(--k-mute);border-radius:99vmin;
  padding:2.2vmin 4vmin;min-width:16vmin;cursor:pointer}
button.on,button.primary{background:var(--k-accent);border-color:var(--k-accent);color:#1b1206}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-variant-numeric:tabular-nums}
.mute{color:var(--k-mute)}

body{align-items:stretch;justify-content:flex-start;gap:2vmin}
header{display:flex;align-items:center;justify-content:space-between;gap:2vmin}
textarea{flex:1;width:100%;resize:none;border:.3vmin solid color-mix(in srgb,var(--k-mute) 45%,transparent);border-radius:2vmin;
  background:color-mix(in srgb,var(--k-fg) 6%,transparent);color:var(--k-fg);font:4vmin/1.6 inherit;padding:2.5vmin;outline:none;
  -webkit-user-select:text;user-select:text}
textarea:focus{border-color:var(--k-accent)}
header button{min-width:0;padding:1.4vmin 3vmin;font-size:3vmin}
#info{font-size:2.8vmin}
</style></head><body>
<header><h1>メモ</h1><span id="info" class="mute"></span><button id="clear">消去</button></header>
<textarea id="t" placeholder="ここに書いた内容は、このiPadの中に自動で保存されます。"></textarea>
<script>
var t=document.getElementById('t'),info=document.getElementById('info'),KEY='kukan.memo',armed=0;
function load(){try{return localStorage.getItem(KEY)||''}catch(e){return ''}}
function save(){try{localStorage.setItem(KEY,t.value);info.textContent=t.value.length+'文字・保存済み'}catch(e){info.textContent='保存できませんでした'}}
t.value=load();info.textContent=t.value.length+'文字';
t.addEventListener('input',save);
document.getElementById('clear').onclick=function(){
  if(!armed){armed=1;this.textContent='もう一度押すと消去';this.classList.add('on');var b=this;setTimeout(function(){armed=0;b.textContent='消去';b.classList.remove('on')},3000);return}
  armed=0;this.textContent='消去';this.classList.remove('on');t.value='';save();};
</script></body></html>
"""#

    static let ambientHTML = #"""
<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>環境音</title>
<style>:root{--k-bg:#141d3a;--k-fg:#e9edf9;--k-mute:#95a2c6;--k-accent:#ffb454}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--k-bg);color:var(--k-fg);font-family:-apple-system,"Hiragino Sans","Yu Gothic UI",system-ui,sans-serif;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3vmin;padding:4vmin;overflow:hidden;
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
h1{margin:0;font-size:3.2vmin;font-weight:600;letter-spacing:.18em;color:var(--k-mute)}
.row{display:flex;gap:2vmin;flex-wrap:wrap;justify-content:center}
button{font:600 3.6vmin/1 inherit;color:var(--k-fg);background:transparent;border:.4vmin solid var(--k-mute);border-radius:99vmin;
  padding:2.2vmin 4vmin;min-width:16vmin;cursor:pointer}
button.on,button.primary{background:var(--k-accent);border-color:var(--k-accent);color:#1b1206}
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-variant-numeric:tabular-nums}
.mute{color:var(--k-mute)}

canvas{width:80vw;height:18vmin}
#sounds button{min-width:22vmin}
label{display:flex;align-items:center;gap:2vmin;font-size:3.2vmin}
input[type=range]{width:44vw;accent-color:var(--k-accent)}
#note{font-size:2.8vmin}
</style></head><body>
<h1>環境音</h1>
<canvas id="c" width="640" height="140"></canvas>
<div class="row" id="sounds"><button data-s="rain">雨</button><button data-s="wave">波</button><button data-s="wind">風</button></div>
<label>音量<input id="vol" type="range" min="0" max="100" value="60"></label>
<div id="note" class="mute">ボタンで鳴らす／もう一度押すと止まる。重ねて鳴らせます。</div>
<script>
var ac=null,master=null,an=null,playing={},data=null;
function setup(){if(ac)return;ac=new (window.AudioContext||window.webkitAudioContext)();master=ac.createGain();an=ac.createAnalyser();an.fftSize=128;
  data=new Uint8Array(an.frequencyBinCount);master.gain.value=document.getElementById('vol').value/100*.8;master.connect(an);an.connect(ac.destination);}
function noise(){var n=ac.sampleRate*3,buf=ac.createBuffer(1,n,ac.sampleRate),d=buf.getChannelData(0),last=0;
  for(var i=0;i<n;i++){var w=Math.random()*2-1;last=(last+.02*w)/1.02;d[i]=w*.35+last*2.2;}
  var s=ac.createBufferSource();s.buffer=buf;s.loop=true;return s;}
function make(kind){var src=noise(),f=ac.createBiquadFilter(),g=ac.createGain(),nodes=[src];
  if(kind==='rain'){f.type='highpass';f.frequency.value=1400;g.gain.value=.5;}
  if(kind==='wave'){f.type='lowpass';f.frequency.value=520;g.gain.value=.5;var l=ac.createOscillator(),lg=ac.createGain();l.frequency.value=.11;lg.gain.value=.42;l.connect(lg);lg.connect(g.gain);l.start();nodes.push(l);}
  if(kind==='wind'){f.type='bandpass';f.frequency.value=420;f.Q.value=.7;g.gain.value=.7;var l2=ac.createOscillator(),lg2=ac.createGain();l2.frequency.value=.07;lg2.gain.value=260;l2.connect(lg2);lg2.connect(f.frequency);l2.start();nodes.push(l2);}
  src.connect(f);f.connect(g);g.connect(master);src.start();return {gain:g,nodes:nodes};}
document.querySelectorAll('#sounds button').forEach(function(b){b.onclick=function(){setup();ac.resume();var k=b.dataset.s;
  if(playing[k]){playing[k].nodes.forEach(function(n){try{n.stop()}catch(e){}});playing[k].gain.disconnect();delete playing[k];b.classList.remove('on');}
  else{playing[k]=make(k);b.classList.add('on');}};});
document.getElementById('vol').oninput=function(){if(master)master.gain.value=this.value/100*.8;};
var c=document.getElementById('c'),x=c.getContext('2d');
function draw(){requestAnimationFrame(draw);var w=c.width,h=c.height,n=40,bw=w/n,cs=getComputedStyle(document.documentElement);
  x.clearRect(0,0,w,h);var on=an&&Object.keys(playing).length;if(on)an.getByteFrequencyData(data);
  for(var i=0;i<n;i++){var v=on?data[i]/255:0,bh=4+v*(h-10);x.fillStyle=v>.03?cs.getPropertyValue('--k-accent'):cs.getPropertyValue('--k-mute');x.fillRect(i*bw+2,(h-bh)/2,bw-4,bh);}}
draw();
</script></body></html>
"""#

}
