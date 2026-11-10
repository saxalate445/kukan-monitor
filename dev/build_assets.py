#!/usr/bin/env python3
"""dev/ 以下のスクリプトとウィジェットHTMLから KukanMonitor.swiftpm/WebAssets.swift を作る。

使い方: python3 dev/build_assets.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'KukanMonitor.swiftpm', 'WebAssets.swift')
WIDGETS = [('clock', '時計'), ('timer', 'タイマー'), ('memo', 'メモ'), ('ambient', '環境音')]


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding='utf-8') as f:
        return f.read()


def literal(text):
    assert '"""#' not in text and '\\#(' not in text
    return '#"""\n' + text.rstrip('\n') + '\n"""#'


base = read('widgets', '_base.css')
out = []
out.append('import Foundation\n')
out.append('/// ページに読み込ませる補助スクリプトと、内蔵ウィジェットのHTML。')
out.append('/// このファイルは dev/build_assets.py が自動生成します。直接は編集しないでください。')
out.append('enum WebAssets {')
out.append('    /// 内蔵ウィジェット用の、実在しない専用アドレス（.invalid は予約済みで、どこにもつながらない）')
out.append('    static let widgetHost = "widgets.kukan.invalid"\n')
out.append('    static let widgets: [(id: String, name: String)] = [')
out.append(',\n'.join('        (id: "%s", name: "%s")' % w for w in WIDGETS))
out.append('    ]\n')
out.append('''    static func widgetURLString(_ id: String) -> String {
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
        switch id {''')
for wid, _ in WIDGETS:
    out.append('        case "%s": return %sHTML' % (wid, wid))
out.append('''        default: return nil
        }
    }
''')
out.append('    static let bootstrapScript = ' + literal(read('bootstrap.js')) + '\n')
for wid, _ in WIDGETS:
    html = read('widgets', wid + '.html').replace('/*BASE*/', base)
    out.append('    static let %sHTML = ' % wid + literal(html) + '\n')
out.append('}')
with open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
print('wrote', os.path.normpath(OUT))
