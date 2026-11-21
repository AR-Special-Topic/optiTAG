# Firebase Cloud Function：Speech-to-Text V2

## 已實作的介面

App → Firebase Auth（自動匿名登入）→ callable `transcribeSpeech`（`asia-southeast1`，強制 App Check）→ Google STT V2。

後端固定 `chirp_2`、`cmn-Hant-TW`、16kHz／單聲道／little-endian PCM16，使用 `recognizers/_`，不必先建立 Recognizer。每段最多 50 秒（1,600,000 bytes）；App 送出 `{ "pcm": "base64…" }`，後端回傳 `{ "segments": [{ "start": 0.0, "end": 0.5, "text": "文字" }] }`。時間相對當次區塊，App 加回原錄音 offset。只有成功的空陣列算無語音；錯誤與缺少時間戳都保留錄音。

後端不另存音訊或逐字稿，也不記錄原始請求／上游錯誤文字。失敗時僅記錄診斷編號、階段、例外類型、錯誤代碼、revision 與不含區域變數的程式位置；App 顯示相同診斷編號供對照。Google STT 本身依專案服務設定處理音訊。Function 使用 runtime service account 的 ADC，不需 API key 或私鑰檔。最大 instances=2、concurrency=4；這是併發限制，並非每日花費上限或每個使用者的用量配額。

## 部署前設定

目前 `.firebaserc` 對應 App 設定檔的專案 `optituck`。若改專案，要同步更新 GoogleService-Info.plist 與 Firebase CLI 的 project。

1. Firebase 專案啟用 Blaze 計費、Authentication → Sign-in method → Anonymous。
2. Google Cloud 啟用 Speech-to-Text API，確認 STT 配額與計費。
3. Function 的 runtime service account 需在相同專案有 `roles/speech.client`（包含 `speech.recognizers.recognize`）。本實作未指定 service account，第二代 Functions 通常使用 `PROJECT_NUMBER-compute@developer.gserviceaccount.com`；請從部署後 Function 的 Runtime 設定確認實際身分，僅授予該帳戶必要權限。部署帳戶還需 Functions 部署與 service account 使用權限。
4. Firebase App Check 登錄對應 iOS app。Debug build 使用 `AppCheckDebugProviderFactory`；在 Xcode Scheme → Run → Arguments 加入 `-FIRDebugEnabled`，首次執行從 Xcode console 取得 debug token，登錄到 Firebase Console → App Check → 該 App → Manage debug tokens。不要把 token 提交到 Git。
5. Release 使用 App Attest；在 Apple Developer／Xcode 啟用 App Attest capability 並更新 provisioning，Firebase Console 登錄 App Attest provider。entitlements 使用 production 環境。若 Personal Team 不支援此 capability，先使用 Debug provider 做開發測試，Release 需可使用 App Attest 的簽章設定。AI Logic 也會使用同一 App Check provider。

## 部署

需要 Firebase CLI、已登入且有部署權限的 Google 帳戶，以及 Python 3.12。本次開發環境沒有 Firebase CLI 或部署登入資訊，程式建置成功不代表已部署。

從專案根目錄執行：

```sh
firebase login
python3.12 -m venv functions/venv
functions/venv/bin/python -m pip install -r functions/requirements.txt
firebase deploy --only functions:speech --project optituck
```

若 runtime service account 尚無 Speech Client 權限，請在 Google Cloud IAM 授予後再測試。Function 為 callable endpoint，Cloud Run 的 invocation 設定需允許 Firebase client SDK 抵達；身分與 App Check 驗證由 callable handler 執行，不能以一般 Google IAM token 取代 Firebase Auth token。

## 驗證

```sh
functions/venv/bin/python -m unittest discover -s functions -v
zsh Tests/run-contract-checks.sh
```

真機 XR：完成 debug token 登錄後下載一段繁中語音，確認時間戳及摘要；無語音應清理錄音，斷網／未授權／配額錯誤應保留錄音。支援 Apple Speech 的裝置仍優先使用本機辨識，因此不一定會呼叫後端。App 取消會停止接下來的區塊；已送出的 Function 工作可能仍完成並產生費用，未自動重試上游 STT。

官方參考：[Callable Functions](https://firebase.google.com/docs/functions/callable)、[App Check](https://firebase.google.com/docs/app-check/ios/app-attest-provider)、[匿名登入](https://firebase.google.com/docs/auth/ios/anonymous-auth)、[Chirp 2 與逐字時間戳](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-2)。

## App 顯示 INTERNAL

`INTERNAL` 是 callable 的通用內部錯誤，單憑這個字串無法判定根因。App 會顯示 Google STT 失敗的錄音區段與 Firebase 錯誤 domain/code；錄音保留供重試。請在 Firebase／Google Cloud Console 查看 `asia-southeast1` 的 `transcribeSpeech` 同時段執行紀錄，確認部署版本、Speech API、計費與 runtime service account 權限。若沒有對應執行紀錄，也需確認 App 的 Firebase 專案設定與 callable 部署位置。不要把原始音訊、逐字稿或憑證加入日誌。

修正後按「重試轉寫」，不必重新下載。更新 App 的錯誤提示並不會修復尚未確認的後端問題。

後端診斷修改需重新部署 `functions:speech` 才會生效；只更新 iOS App 不會更新 Cloud Function。新錯誤訊息包含「診斷」與 config／client／recognize／segments 階段。若仍只有 INTERNAL，需檢查 callable handler 之前的驗證或平台日誌，不能推定為 Speech API 錯誤。

## 逐字時間超出錄音範圍

實測同一段 2.558625 秒 PCM 的多個尾字時間連續超出錄音終點。若時間有限、非負且 start ≤ end，但超出錄音範圍，改將該次請求所有 result 的完整辨識文字合為一個 segment，來源時間為整段 PCM 的 0–duration（每段最多 50 秒）。不裁切多個尾字成零長度區段、不丟棄尾字、不當成無語音，也不再逐次放寬容差。此時引用只能定位到整個區塊，不能視為精確逐字時間；這不保證辨識文字本身正確。正常範圍內的逐字時間仍保留；缺少逐字時間、倒序、負值與非有限值仍報錯並保留錄音。
