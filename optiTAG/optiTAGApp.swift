//
//  optiTAGApp.swift
//  optiTAG
//
//  Created by Paul Weng on 5/8/26.
//

// 負責啟動的地方

import SwiftUI
#if DEBUG
import FirebaseCore
import FirebaseAppCheck
#endif

@main
struct optiTAGApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-OptiTAGShowAppCheckDebugToken") else { return }
                    do {
                        try FirebaseSpeechBackend.configure()
                        if let app = FirebaseApp.app(), let provider = AppCheckDebugProvider(app: app) {
                            print("optiTAG App Check debug token: \(provider.localDebugToken())")
                        }
                        AppCheck.appCheck().token(forcingRefresh: true) { token, error in
                            if let error {
                                let failure = error as NSError
                                print("optiTAG App Check 驗證失敗（\(failure.domain)，代碼 \(failure.code)）")
                            } else if token != nil {
                                print("optiTAG App Check 驗證成功")
                            } else {
                                print("optiTAG App Check 驗證失敗：Firebase 未回傳憑證")
                            }
                        }
                    } catch {
                        print("optiTAG App Check setup failed: \(error.localizedDescription)")
                    }
                }
                #endif
        }
    }
}
