#!/usr/bin/env swift
// WebKit content-blocker JSONのコンパイル検証 (macOSのWebKitで実行)。
// WebKitは1件でも不正ルールがあるとリスト全体のコンパイルに失敗するため、
// 実機投入前の自動チェックとして使う。iOSとmacOSでエンジン(WebCore)は共通。
// 使い方: swift validate_blocklists.swift <Listsディレクトリ>
import Foundation
import WebKit

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift validate_blocklists.swift <Lists dir>\n", stderr)
    exit(2)
}
let dir = CommandLine.arguments[1]
let fm = FileManager.default
guard let files = try? fm.contentsOfDirectory(atPath: dir) else {
    fputs("cannot list \(dir)\n", stderr)
    exit(2)
}
let parts = files.filter { $0.hasPrefix("wvb-ubo-part-") && $0.hasSuffix(".json") }.sorted()
if parts.isEmpty {
    fputs("no wvb-ubo-part-*.json in \(dir)\n", stderr)
    exit(2)
}
guard let store = WKContentRuleListStore.default() else {
    fputs("WKContentRuleListStore unavailable\n", stderr)
    exit(2)
}

var failures = 0
for part in parts {
    let id = "wvb-validate-" + part
    let path = (dir as NSString).appendingPathComponent(part)
    guard let json = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL \(part): unreadable")
        failures += 1
        continue
    }
    var done = false
    var ok = false
    var errMsg = ""
    store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { _, error in
        if let error = error as NSError? {
            errMsg = "\(error.domain) code=\(error.code) \(error.localizedDescription)"
            if let underlying = error.userInfo[NSUnderlyingErrorKey] {
                errMsg += " underlying=\(underlying)"
            }
        } else {
            ok = true
        }
        done = true
    }
    let deadline = Date(timeIntervalSinceNow: 300)
    while !done && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    if !done {
        print("FAIL \(part): timeout")
        failures += 1
        continue
    }
    // 検証用IDは後片付け
    let removed = DispatchSemaphore(value: 0)
    store.removeContentRuleList(forIdentifier: id) { _ in removed.signal() }
    _ = removed.wait(timeout: .now() + 30)
    if ok {
        print("OK \(part) (\(json.utf8.count / 1024) KB)")
    } else {
        print("FAIL \(part): \(errMsg)")
        failures += 1
    }
}
if failures > 0 {
    print("\(failures) list(s) FAILED")
    exit(1)
}
print("all \(parts.count) list(s) compiled successfully")
