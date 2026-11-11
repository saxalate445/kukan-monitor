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

  function ensureStyle() {
    if (!document.getElementById(STYLE_ID)) {
      var st = document.createElement('style');
      st.id = STYLE_ID;
      st.textContent = CSS;
      (document.head || document.documentElement).appendChild(st);
    }
  }

  function clearFill() {
    document.querySelectorAll('[data-kukan-fill],[data-kukan-fill-anc],[data-kukan-fill-mid]').forEach(function (el) {
      el.removeAttribute('data-kukan-fill');
      el.removeAttribute('data-kukan-fill-anc');
      el.removeAttribute('data-kukan-fill-mid');
    });
    document.documentElement.removeAttribute('data-kukan-fill-on');
  }

  // 指定した要素を画面（＝モニターの枠）いっぱいにする
  function applyChain(target, video) {
    ensureStyle();
    var root = document.documentElement;
    target.setAttribute('data-kukan-fill', '');
    for (var p = target.parentElement; p && p !== root; p = p.parentElement) p.setAttribute('data-kukan-fill-anc', '');
    if (video && video !== target) {
      for (var m = video.parentElement; m && m !== target; m = m.parentElement) m.setAttribute('data-kukan-fill-mid', '');
    }
    root.setAttribute('data-kukan-fill-on', '');
    window.dispatchEvent(new Event('resize'));
  }

  function notifyFill(on) {
    K.fillOn = !!on;
    try { window.webkit.messageHandlers.kukanFill.postMessage({ fill: !!on }); } catch (_) {}
  }

  K.fillOn = false;
  // 戻り値：'on'（広げた）/ 'off'（戻した）/ 'none'（動画が見つからない）
  K.fill = function (on) {
    if (!on) {
      clearFill();
      notifyFill(false);
      window.dispatchEvent(new Event('resize'));
      return 'off';
    }
    clearFill();
    var pick = pickTarget();
    if (!pick) return 'none';
    applyChain(pick.target, pick.video);
    notifyFill(true);
    return 'on';
  };

  // ---- 全画面：ページの「全画面」ボタンを、モニターの枠の中での全画面に差し替える ----
  // iPadの画面全体を乗っ取らず、空間に浮かんだモニターの中だけで全画面にする。
  (function shimFullscreen() {
    var fsElement = null;
    function fire() {
      ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (name) {
        var e;
        try { e = new Event(name, { bubbles: true }); } catch (_) { e = document.createEvent('Event'); e.initEvent(name, true, false); }
        document.dispatchEvent(e);
      });
    }
    function enter(el) {
      fsElement = el || document.documentElement;
      clearFill();
      var v = (fsElement.tagName && fsElement.tagName.toLowerCase() === 'video') ? fsElement
            : (fsElement.querySelector ? fsElement.querySelector('video') : null);
      applyChain(fsElement, v);
      notifyFill(true);
      fire();
      return Promise.resolve();
    }
    function leave() {
      fsElement = null;
      clearFill();
      notifyFill(false);
      window.dispatchEvent(new Event('resize'));
      fire();
      return Promise.resolve();
    }
    function set(obj, name, fn) { try { obj[name] = fn; } catch (_) {} }
    set(Element.prototype, 'requestFullscreen', function () { return enter(this); });
    set(Element.prototype, 'webkitRequestFullscreen', function () { return enter(this); });
    set(Element.prototype, 'webkitRequestFullScreen', function () { return enter(this); });
    set(document, 'exitFullscreen', leave);
    set(document, 'webkitExitFullscreen', leave);
    set(document, 'webkitCancelFullScreen', leave);
    function getter(name, fn) { try { Object.defineProperty(document, name, { configurable: true, get: fn }); } catch (_) {} }
    getter('fullscreenElement', function () { return fsElement; });
    getter('webkitFullscreenElement', function () { return fsElement; });
    getter('webkitCurrentFullScreenElement', function () { return fsElement; });
    getter('fullscreenEnabled', function () { return true; });
    getter('webkitFullscreenEnabled', function () { return true; });
    if (window.HTMLVideoElement) {
      set(HTMLVideoElement.prototype, 'webkitEnterFullscreen', function () { enter(this); });
      set(HTMLVideoElement.prototype, 'webkitExitFullscreen', function () { leave(); });
      set(HTMLVideoElement.prototype, 'webkitSetPresentationMode', function (mode) { if (mode === 'fullscreen') { enter(this); } else { leave(); } });
    }
    K.exitFullscreen = function () { if (fsElement) leave(); };
  })();

  // ---- ウィジェット用：アプリのテーマ色を受け取る ----
  K.setTheme = function (bg, fg, mute, accent) {
    var s = document.documentElement.style;
    s.setProperty('--k-bg', bg); s.setProperty('--k-fg', fg);
    s.setProperty('--k-mute', mute); s.setProperty('--k-accent', accent);
    return true;
  };
  void top;
})();
