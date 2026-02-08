# 遠端部署完整指南

本文檔基於本地 Docker 整合測試與 GCP 實際部署中發現的 28+ 個問題，整理出一次到位的遠端部署流程。

---

## 快速部署流程 (Step by Step)

> 以下是完整部署的精簡步驟清單。每一步的詳細說明請見對應章節。

```
前置作業
  ① 準備兩台 Linux 伺服器（建議 Debian 12 / Ubuntu 22.04，各 4GB+ RAM）
  ② 記下兩台的 Public IP 和 Internal IP（同 VPC 內網 IP）
  ③ 確認防火牆允許：TCP 80, 443（對外）+ 內網全通（跨節點 9986, 9643）

安裝環境（兩台都要）
  ④ 上傳 vm-init.sh 到伺服器：
     gcloud compute scp deployment-project/vm-init.sh VM_NAME:/tmp/ --zone=ZONE
  ⑤ SSH 進入伺服器執行：
     sudo bash /tmp/vm-init.sh     # 安裝 Docker、Docker Compose、常用工具

生成設定檔（在本機執行）
  ⑥ cd deployment-project && bash setup.sh
     # 輸入 Public IP、Internal IP、密碼（可留空自動產生）、SSL 憑證路徑（留空自簽）
  ⑦ 複製遊戲客戶端到 game-node/client-dist/：
     cp -r ../遊戲客戶端/plinko/outsource/build/* game-node/client-dist/
  ⑧（可選）壓縮 DB migration：bash squash_db.sh

上傳到伺服器（詳見 Section 6）
  ⑨ 上傳到兩台伺服器的 /opt/deploy/：
     Admin Node 需要：後台/、deployment-project/
     Game Node  需要：遊戲服務器/、deployment-project/
     # 最簡單：兩台都傳整個專案根目錄
  ⑨b SSH 到各 VM 執行驗證（ls 確認目錄齊全，特別是 .env 和 certs/）

部署（順序重要！）
  ⑩ 先啟動 Game Node：
     ssh game-server
     cd /opt/deploy/deployment-project/game-node
     sudo docker compose up -d --build
     sudo docker compose ps          # 等 gamehub 顯示 healthy

  ⑪ 再啟動 Admin Node：
     ssh admin-server
     cd /opt/deploy/deployment-project/admin-node
     sudo docker compose up -d --build
     sudo docker compose logs -f backend  # 看到 "Starting backend for real..." 即成功

驗證
  ⑫ 瀏覽器開啟 https://ADMIN_IP/manager
     → 接受自簽憑證警告 → 登入 dccuser / 12345678
     → 確認左側選單完整、無白屏
  ⑬ 瀏覽器開啟 https://GAME_IP/
     → 確認遊戲頁面可載入（需透過 channelHandle 才能實際遊玩）
```

---

## 目錄

1. [系統架構](#1-系統架構)
2. [前置準備](#2-前置準備)
3. [設定檔生成（setup.sh）](#3-設定檔生成)
4. [資料庫遷移壓縮（squash_db.sh）](#4-資料庫遷移壓縮)
5. [準備遊戲客戶端](#5-準備遊戲客戶端)
6. [上傳到伺服器](#6-上傳到伺服器)
7. [部署 Game Node（先）](#7-部署-game-node先)
8. [部署 Admin Node（後）](#8-部署-admin-node後)
9. [驗證部署](#9-驗證部署)
10. [常見問題 Q&A](#10-常見問題-qa)
11. [目錄結構](#11-目錄結構)
12. [本地測試](#12-本地測試)
13. [除錯指令速查](#13-除錯指令速查)
14. [完整 Port 對照表](#14-完整-port-對照表)

---

## 1. 系統架構

```
                    ┌─── HTTPS (443) ───┐              ┌─── HTTPS (443) ───┐
                    │                   │              │                   │
                    │    Admin Node     │              │    Game Node      │
  瀏覽器 ──────────►│                   │              │                   │◄── 瀏覽器
                    │  nginx (frontend) │  HTTP (內網)  │  nginx (game-client)
                    │  ┌───────────────┐│◄───────────►│  ┌───────────────┐│
                    │  │/manager (靜態) ││  :9986 ↔    │  │/      (遊戲)  ││
                    │  │/agent   (靜態) ││      :9643  │  │/ws    → :10101││
                    │  │/api    → :9986 ││              │  │/gamehub→ :9643││
                    │  │/channel→ :9986 ││              │  └───────────────┘│
                    │  │/chatservice.ws ││              │                   │
                    │  │        → :8896 ││              │  gamehub          │
                    │  │/monitor→:17782 ││              │  postgres (game)  │
                    │  │/dcctools→:8080 ││              │  redis   (game)   │
                    │  └───────────────┘│              └───────────────────┘
                    │                   │
                    │  backend          │
                    │  orderservice     │
                    │  chatservice      │
                    │  monitorservice   │
                    │  dcctools + mysql │
                    │  postgres (admin) │
                    │  redis   (admin)  │
                    └───────────────────┘
```

### 核心設計原則

- **對外只開 80/443**，瀏覽器流量走 nginx HTTPS 反向代理
- **跨節點服務間通訊走 HTTP 內網**（Backend ↔ GameHub 透過 VPC Internal IP，避免自簽憑證 TLS 問題）
- 額外暴露 port 9986（Admin Node）和 9643（Game Node）供內網直連
- 資料庫、Redis 不對外暴露，只能 Docker 內網存取
- 遠端 DB 管理用 SSH tunnel 或 `docker exec`

### 跨節點通訊路徑

| 路徑 | 協定 | 說明 |
|------|------|------|
| GameHub → `http://ADMIN_INTERNAL_IP:9986/api/v1/intercom/creategamerecord` | HTTP (內網) | 遊戲結算通知 → backend |
| Backend → `http://GAME_INTERNAL_IP:9643/getdefaultkilldiveinfo` | HTTP (內網) | 遊戲初始化 → gamehub |
| 瀏覽器 → `wss://GAME_PUBLIC_IP/ws` | WSS (公網) | 遊戲 WebSocket → game nginx → gamehub:10101 |
| 瀏覽器 → `https://ADMIN_PUBLIC_IP/chatservice.ws` | WSS (公網) | 聊天 WebSocket → admin nginx → chatservice:8896 |

> **正式環境**：使用受信任 SSL 憑證（如 Let's Encrypt）後，跨節點也可以走 HTTPS，不需要暴露額外 port。

---

## 2. 前置準備

### 2.1 伺服器需求

| 項目 | Admin Node | Game Node |
|------|-----------|-----------|
| 作業系統 | Debian 12+ / Ubuntu 22.04+ | 同左 |
| Docker | 20.10+ | 同左 |
| Docker Compose | v2.0+ (plugin) | 同左 |
| 記憶體 | 建議 4GB+ | 建議 2GB+ |
| 硬碟 | 建議 20GB+ | 建議 10GB+ |

### 2.2 安裝 Docker 環境

兩台伺服器都需要先安裝 Docker。可使用專案內的 `vm-init.sh`：

```bash
# 從本機上傳腳本（GCP 範例）
gcloud compute scp deployment-project/vm-init.sh admin-node:/tmp/ --zone=asia-east1-b
gcloud compute scp deployment-project/vm-init.sh game-node:/tmp/ --zone=asia-east1-b

# SSH 到各 VM 執行
gcloud compute ssh admin-node --zone=asia-east1-b
sudo bash /tmp/vm-init.sh    # 安裝 Docker CE、Docker Compose plugin、curl、htop 等
```

> **注意**：如果從 Windows 上傳 .sh 檔案，在 Linux 上執行前先轉換換行符號：`sed -i 's/\r$//' /tmp/vm-init.sh`

### 2.3 防火牆

**對外（公網）**：
```
TCP 80   (HTTP → 自動 redirect 到 HTTPS)
TCP 443  (HTTPS，瀏覽器存取入口)
```

**內網（跨節點）**：
```
TCP 9986  (Admin Node → Backend API，供 GameHub 結算回呼)
TCP 9643  (Game Node → GameHub API，供 Backend 初始化)
```

> GCP 同一 VPC 預設有 `default-allow-internal` 規則，內網 port 自動全通，不需要額外設定。
> 公網防火牆指令可用 `bash gcloud_firewall.sh` 查看。

### 2.4 SSL 憑證

setup.sh 支援兩種方式：
- **自簽憑證**：留空自動產生（測試用，瀏覽器會出現警告）
- **正式憑證**：提供 fullchain.pem + privkey.pem 路徑（如 Let's Encrypt）

### 2.5 本機需要的檔案

確保專案根目錄下有以下資料夾：
```
後台/platform-ete/              ← Backend 原始碼
後台/orderservice-main/         ← OrderService 原始碼
後台/chatservice-main/          ← ChatService 原始碼
後台/monitorservice-develop/    ← MonitorService 原始碼
後台/後台前端頁面/dcc_front/     ← 前端原始碼
後台/測試client(同花順)/dcctools/ ← DCC Tools 原始碼
遊戲服務器/GameHub/              ← GameHub 原始碼
遊戲服務器/deployments/gamehub/sql/ ← 遊戲 SQL 初始化檔
遊戲客戶端/plinko/outsource/build/  ← 遊戲客戶端編譯產物
```

---

## 3. 設定檔生成

```bash
cd deployment-project
bash setup.sh
```

互動問答：
```
Enter Admin Node Public IP:       ← 填 Admin 伺服器公網 IP
Enter Game Node Public IP:        ← 填 Game 伺服器公網 IP
Enter Admin Node Internal IP:     ← GCP/AWS VPC 內網 IP（留空則用公網 IP）
Enter Game Node Internal IP:      ← GCP/AWS VPC 內網 IP（留空則用公網 IP）
Enter Database Password:          ← 留空自動產生（hex 格式，無特殊字元）
Enter Redis Password:             ← 留空自動產生
SSL fullchain.pem path:           ← 留空產生自簽憑證，或填憑證路徑
```

setup.sh 會自動產生以下檔案：

```
admin-node/
  .env                          ← DB/Redis 密碼、IP
  certs/fullchain.pem, privkey.pem  ← SSL 憑證
  configs/config.yml            ← Backend 設定
  configs/orderservice.yml      ← OrderService 設定
  configs/chatservice.yml       ← ChatService 設定
  configs/monitorservice.yml    ← MonitorService 設定
  db-init/dcctools-schema.sql   ← DCC Tools MySQL schema（從原始碼複製）
  scripts/update_server_info.sql ← 更新 server_info 的 SQL
  scripts/update_game_data.sql  ← 更新遊戲資料、whitelist 的 SQL

game-node/
  .env                          ← DB/Redis 密碼、IP
  certs/fullchain.pem, privkey.pem  ← SSL 憑證
  configs/GameHub.conf          ← GameHub 設定（SettlePlatform 指向內網 HTTP）
  configs/game-client-config.json ← Plinko 客戶端設定（wss:// WebSocket）
  db-init/gamelist.sql          ← 遊戲列表（從原始碼複製）
  db-init/gameinfo.sql          ← 遊戲設定（從原始碼複製）
  db-init/lobbyinfo.sql         ← 大廳設定（從原始碼複製）
```

### 以下檔案是靜態的（已包含在 repo 中，不需要生成）：

```
admin-node/
  configs/nginx.conf            ← HTTPS 反向代理設定
  db-init/init-extra-dbs.sql    ← 建立 dcc_order, dcc_chat, monitor 資料庫
  db-init/dcctools-init.sql     ← DCC Tools MySQL 資料修正

game-node/
  configs/game-client-nginx.conf ← 遊戲客戶端 HTTPS nginx 設定
```

---

## 4. 資料庫遷移壓縮

Backend 有 400+ 個 migration 檔案。可以壓縮成一個 `clean_init.sql` 加速首次啟動：

```bash
bash squash_db.sh
```

這會：
1. 啟動臨時 PostgreSQL 容器
2. 執行所有 migration
3. 匯出 schema + 種子資料（admin_user, agent, game, server_info, storage 等）
4. 合併到 `admin-node/db-init/clean_init.sql`

> **注意**：如果不跑 squash_db.sh，Backend 會在首次啟動時自動跑所有 migration（慢但可行）。如果沒跑 squash_db.sh，確保 `admin-node/db-init/clean_init.sql` 這個檔案不存在或為空，否則 postgres 會嘗試執行它。

---

## 5. 準備遊戲客戶端

```bash
# 在本機的 deployment-project/ 目錄下執行
cp -r ../遊戲客戶端/plinko/outsource/build/* game-node/client-dist/

# 確認複製成功
ls game-node/client-dist/index.html
```

> **注意**：`setup.sh` 不會自動複製遊戲客戶端，必須手動執行此步驟。如果 `client-dist/` 為空，Game Node 的 nginx 會返回 403。

---

## 6. 上傳到伺服器

### 6.1 為什麼要上傳整個專案？

Docker build 的 context 是**專案根目錄**，Dockerfile 中使用相對路徑引用原始碼（如 `COPY 後台/platform-ete/backend/ ./`）。如果只上傳 `deployment-project/`，build 會因為找不到原始碼而失敗。

### 6.2 各節點需要的目錄

| 目錄 | Admin Node | Game Node | 說明 |
|------|:----------:|:---------:|------|
| `deployment-project/` | **必須** | **必須** | Dockerfiles、docker-compose、設定檔 |
| `後台/platform-ete/` | **必須** | - | Backend API 原始碼 |
| `後台/orderservice-main/` | **必須** | - | OrderService 原始碼 |
| `後台/chatservice-main/` | **必須** | - | ChatService 原始碼 |
| `後台/monitorservice-develop/` | **必須** | - | MonitorService 原始碼 |
| `後台/後台前端頁面/dcc_front/frontend/` | **必須** | - | 前端 Vue 原始碼 |
| `後台/測試client(同花順)/dcctools/` | **必須** | - | DCC Tools PHP 原始碼 |
| `遊戲服務器/GameHub/` | - | **必須** | GameHub 原始碼 |
| `遊戲服務器/collie/` | - | **必須** | GameHub 依賴的 collie 模組 |

> **最簡單做法**：兩台都上傳整個專案根目錄，不用區分。磁碟空間足夠的話這樣最不容易漏。

### 6.3 上傳步驟

```bash
# ─── 步驟 1：在兩台 VM 上建立目標目錄 ───
# Admin Node
gcloud compute ssh admin-node --zone=asia-east1-b \
  --command="sudo mkdir -p /opt/deploy && sudo chown \$(whoami) /opt/deploy"
# Game Node
gcloud compute ssh game-node --zone=asia-east1-b \
  --command="sudo mkdir -p /opt/deploy && sudo chown \$(whoami) /opt/deploy"

# ─── 步驟 2：上傳檔案 ───
# 假設本機專案根目錄是 D:\work\new（Windows）或 /home/user/project（Linux）

# 方法 A：GCP gcloud scp（推薦）
gcloud compute scp --recurse "D:\work\new\後台" admin-node:/opt/deploy/後台 --zone=asia-east1-b
gcloud compute scp --recurse "D:\work\new\deployment-project" admin-node:/opt/deploy/deployment-project --zone=asia-east1-b
gcloud compute scp --recurse "D:\work\new\遊戲服務器" game-node:/opt/deploy/遊戲服務器 --zone=asia-east1-b
gcloud compute scp --recurse "D:\work\new\deployment-project" game-node:/opt/deploy/deployment-project --zone=asia-east1-b

# 方法 B：打包後上傳（更快，推薦大專案）
# 本機打包
tar czf /tmp/project.tar.gz -C "D:\work\new" 後台 遊戲服務器 deployment-project
# 上傳到兩台 VM
gcloud compute scp /tmp/project.tar.gz admin-node:/tmp/ --zone=asia-east1-b
gcloud compute scp /tmp/project.tar.gz game-node:/tmp/ --zone=asia-east1-b
# SSH 到各 VM 解壓
tar xzf /tmp/project.tar.gz -C /opt/deploy/

# 方法 C：一般 Linux 伺服器（直接 scp）
scp -r /path/to/project-root/  admin-user@ADMIN_IP:/opt/deploy/
scp -r /path/to/project-root/  game-user@GAME_IP:/opt/deploy/
```

### 6.4 上傳後驗證（重要！）

SSH 到各 VM，確認目錄結構正確：

```bash
# ─── Admin Node 檢查 ───
ls /opt/deploy/
# 應看到：後台/  deployment-project/  （Game Node 還會有 遊戲服務器/）

ls /opt/deploy/後台/
# 應看到：platform-ete/  orderservice-main/  chatservice-main/
#         monitorservice-develop/  後台前端頁面/  測試client(同花順)/

ls /opt/deploy/deployment-project/admin-node/
# 應看到：docker-compose.yml  .env  certs/  configs/  db-init/  scripts/

ls /opt/deploy/deployment-project/admin-node/.env
# 應存在（由 setup.sh 生成），如果不存在代表 setup.sh 沒跑或沒上傳

# ─── Game Node 檢查 ───
ls /opt/deploy/遊戲服務器/
# 應看到：GameHub/  collie/

ls /opt/deploy/deployment-project/game-node/
# 應看到：docker-compose.yml  .env  certs/  configs/  db-init/  client-dist/

ls /opt/deploy/deployment-project/game-node/client-dist/index.html
# 應存在（步驟 5 手動複製），如果不存在遊戲頁面會 403
```

### 6.5 常見漏傳問題

| 漏傳的東西 | 報錯訊息 | 解法 |
|-----------|---------|------|
| `後台/platform-ete/` | `COPY failed: file not found` (backend build) | 上傳 `後台/` 整個目錄 |
| `遊戲服務器/collie/` | `COPY failed: file not found` (gamehub build) | 上傳 `遊戲服務器/collie/` |
| `deployment-project/admin-node/.env` | `variable is not set` | 重新跑 `setup.sh` 或手動上傳 |
| `deployment-project/admin-node/certs/` | nginx 啟動失敗 `cannot load certificate` | 重新跑 `setup.sh`（會生成自簽憑證） |
| `game-node/client-dist/` 為空 | 遊戲頁面 403 Forbidden | 執行步驟 5 複製遊戲客戶端 |
| `game-node/db-init/*.sql` | 遊戲顯示 "Game is close" | 重新跑 `setup.sh`（會複製 SQL） |

> **Windows 注意**：`gcloud compute scp` 底層用 pscp，不支援 `~/` 路徑，請用 `/tmp/` 或 `/opt/deploy/`。

---

## 7. 部署 Game Node（先）

**必須先啟動 Game Node**，因為 Admin Node 的 Backend 在初始化時需要連線 GameHub。

```bash
ssh game-user@GAME_IP       # 或 gcloud compute ssh game-node --zone=ZONE
cd /opt/deploy/deployment-project/game-node
sudo docker compose up -d --build
```

等待所有服務健康：
```bash
sudo docker compose ps
# 確認 gamehub 顯示 (healthy)
```

驗證：
```bash
# 從 Game Node 本機測試（HTTP 直連，不經過 nginx）
curl http://localhost:9643/ping
# 應回傳: pong

# 從外部測試（HTTPS 經過 nginx）
curl -k https://GAME_IP/gamehub/ping
```

---

## 8. 部署 Admin Node（後）

```bash
ssh admin-user@ADMIN_IP     # 或 gcloud compute ssh admin-node --zone=ZONE
cd /opt/deploy/deployment-project/admin-node
sudo docker compose up -d --build
```

Backend 啟動流程（全自動，由 entrypoint.sh 處理）：
1. **第一次啟動**（30 秒 timeout）→ 執行 DB migration → 預期會 timeout 退出
2. **修正 DB** → 用 psql 更新 server_info、game.h5_link、agent whitelist、GameKillDiveInfoReset
3. **等待 GameHub** → 最多等 180 秒（curl `http://GAME_INTERNAL_IP:9643/ping`）
4. **第二次啟動** → 正式運行

監控啟動過程：
```bash
sudo docker compose logs -f backend
```

看到 `[entrypoint] Starting backend for real...` 後，等幾秒直到看到正常的服務日誌。

---

## 9. 驗證部署

### 9.1 基礎健康檢查

```bash
# Game Node
curl -k https://GAME_IP/                       # 遊戲客戶端（應返回 HTML）
curl -k https://GAME_IP/gamehub/ping           # GameHub API

# Admin Node
curl -k https://ADMIN_IP/manager               # 管理後台（應 redirect 或返回 HTML）
curl -k https://ADMIN_IP/api/v1/health/health  # Backend API
```

### 9.2 瀏覽器驗證

1. 開啟 `https://ADMIN_IP/manager`
   - 自簽憑證會出現警告，點「進階」→「繼續前往」
   - 應看到登入頁面

2. 登入（`dccuser` / `12345678`）
   - 應成功登入，左側選單完整顯示
   - **如果白屏**：見 Q&A

3. 確認 Chat 連線
   - 登入後打開瀏覽器 DevTools → Console
   - 不應該看到 chatServiceStore 的 throw 錯誤

4. 測試遊戲流程
   - 從 `https://ADMIN_IP/dcctools/` 發起遊戲請求
   - 進入遊戲 → 玩幾把 → 回管理後台查看注單記錄

---

## 10. 常見問題 Q&A

### Q1: Backend 一直 restart，看不到 healthy？

**A**: 檢查 backend log：

```bash
docker compose logs -f backend
```

常見原因：
- **DB 連不上**：檢查 `configs/config.yml` 的 `database.conn_info`，host 應為 `postgres`（compose service name），密碼要和 `.env` 一致
- **GameHub 連不上**：entrypoint 會等 GameHub 最多 180 秒。確認 Game Node 已啟動且 `curl http://GAME_INTERNAL_IP:9643/ping` 有回應
- **gameKillInfo 初始化失敗**：Backend 啟動時會從 GameHub 拉取遊戲賠率資料。如果 `server_info` 表裡 `dev01` 的 notification URL 不對，或 GameHub 的遊戲資料表為空，就會失敗

**背景知識**：Backend 有個啟動流程會讀取 `storage.GameKillDiveInfoReset`，如果 `flag: true` 就呼叫 GameHub API 拉遊戲賠率。如果第一次失敗了，flag 會被設為 `false`，後續重啟都不會再試 → 永遠無法初始化。entrypoint 會在每次啟動時重置 flag 為 `true` 來解決這個問題。

---

### Q2: 登入後白屏？

**A**: 白屏通常有 3 種原因，按機率排序：

**原因 1 — ChatService 連不上（最常見）**

登入後前端會執行 `chatServiceStore.getChatServiceConn()`。它會從 Backend API 拿到 `server_info` 中 `chat` 的連線資訊（domain + scheme），然後嘗試建立 WebSocket 連線。如果連不上，JS 直接 throw → 白屏。

檢查：
```bash
# 進 admin-postgres 查看 server_info
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT code, addresses FROM server_info WHERE code IN ('chat', 'api', 'monitor');"
```

正確的值（遠端部署）：
```
chat    → addresses 包含 {"domain": "ADMIN_IP", "scheme": "https", ...}
api     → addresses 包含 {"domain": "ADMIN_IP", "scheme": "https", ...}
monitor → addresses 包含 {"domain": "ADMIN_IP", "scheme": "https", ...}
```

如果不對，Backend entrypoint 應該自動修正。確認環境變數 `ADMIN_HOST` 和 `SERVICE_SCHEME` 是否正確。

**原因 2 — 前端資源 404**

打開 DevTools → Network，看有沒有 JS/CSS 檔案 404。如果有，代表 Vite build 時 `base` 路徑沒設定好，或 nginx 設定問題。

**原因 3 — 登入回傳錯誤碼 46**

錯誤碼 46 = IP 白名單被擋。Backend 登入流程會檢查 `agent.ip_whitelist`（注意：是 agent 表，不是 admin_user 表）。entrypoint 會自動設定 `ip_whitelist = [{"ip_address":"*"}]`，如果還是被擋：

```bash
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT id, code, ip_whitelist FROM agent LIMIT 5;"
```

---

### Q3: GameHub 顯示 "Game is close"？

**A**: GameHub 的遊戲資料表（gamelist, gameinfo, lobbyinfo）是空的。

檢查：
```bash
docker exec game-postgres psql -U postgres -d dayon_demo \
  -c "SELECT * FROM gamelist;"
```

如果是空的，代表 game SQL init 沒有正確執行。原因可能是：
- `game-node/db-init/` 裡沒有 SQL 檔案 → 重新跑 `setup.sh`
- PostgreSQL volume 已經存在舊資料 → `docker-entrypoint-initdb.d` 只在**首次初始化**時執行

**解法**：如果 volume 已存在但資料表為空，手動執行：
```bash
docker exec -i game-postgres psql -U postgres -d dayon_demo < game-node/db-init/gamelist.sql
docker exec -i game-postgres psql -U postgres -d dayon_demo < game-node/db-init/gameinfo.sql
docker exec -i game-postgres psql -U postgres -d dayon_demo < game-node/db-init/lobbyinfo.sql
```

或者刪除 volume 重建（**會清除所有遊戲資料**）：
```bash
docker compose down -v
docker compose up -d --build
```

---

### Q4: 遊戲頁面空白（Plinko 載入失敗）？

**A**: 可能原因：

**原因 1 — JS/CSS 被 SPA fallback 攔截**

如果 nginx 的 `try_files` 把 JS/CSS 請求導向 `index.html`，瀏覽器會嘗試把 HTML 當 JS 解析 → `Unexpected token '<'` 錯誤。

`game-client-nginx.conf` 必須有靜態資源規則（已在我們的設定中）：
```nginx
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|bin|json|wasm)$ {
    try_files $uri =404;
}
```

**原因 2 — config.json 沒有或 ServerUrl 不對**

Plinko 客戶端啟動時會 fetch `/config.json` 來取得 WebSocket 伺服器地址。

檢查：
```bash
curl -k https://GAME_IP/config.json
```

應返回：
```json
{
    "ServerUrl": "wss://GAME_IP/ws",
    ...
}
```

如果返回的是 index.html 內容，代表 config.json 沒有掛載成功。確認 `game-node/configs/game-client-config.json` 存在，且 docker-compose 有掛載。

**原因 3 — WebSocket 連不上**

瀏覽器 DevTools → Console 看有沒有 WebSocket 連線錯誤。`wss://GAME_IP/ws` 應該透過 nginx 代理到 gamehub:10101。

---

### Q5: channelHandle API 回傳 "ip is not allow"？

**A**: Backend 的 channelHandle 會檢查 `agent.api_ip_whitelist`（注意不是 `ip_whitelist`，兩個欄位功能不同）。

- `ip_whitelist`：控制管理後台登入的 IP 白名單
- `api_ip_whitelist`：控制 channelHandle API 的 IP 白名單

entrypoint 會自動設定兩者，但 Backend 有 **Agent Cache 機制** — agent 資料在啟動時載入到記憶體，之後修改 DB 不會立即生效。

**解法**：
```bash
docker compose restart backend
```

重啟後 Backend 會重新載入 agent cache。

---

### Q6: channelHandle API 回傳 "agent is not exist"？

**A**: channelHandle 的 `agent_id` 參數是 agent 表的**主鍵 ID（整數）**，不是 agent 的 code 字串。

另外，`top_agent_id = -1` 的頂級代理會被拒絕（程式碼明確 reject top agents）。必須使用子代理。

DCC Tools 的 MySQL 中 `agent.agent_id` 欄位要設定為平台子代理的 PK（例如 5），且 `md5_key`、`aes_key` 要與平台 agent 表一致。

---

### Q7: 遊戲結算後平台看不到注單？

**A**: 遊戲結算流程：

```
GameHub → POST http://ADMIN_INTERNAL_IP:9986/api/v1/intercom/creategamerecord → backend
Backend → 寫入 dcc_game.game_users_stat + dcc_order.user_play_log
```

排查步驟：

1. 確認 GameHub.conf 的 `SettlePlatform.DEV` 指向 `http://ADMIN_INTERNAL_IP:9986/`
2. 確認 admin nginx 的 `/api` location 正確代理到 backend:9986
3. 檢查 backend log：
   ```bash
   docker compose logs backend | grep -i "creategamerecord\|record"
   ```
4. 檢查 DB：
   ```bash
   docker exec admin-postgres psql -U postgres -d dcc_order \
     -c "SELECT bet_id, agent_id, username, game_id, ya_score, de_score FROM user_play_log ORDER BY create_time DESC LIMIT 5;"
   ```

---

### Q8: 更新原始碼後如何重新部署？

**A**:

```bash
# 1. 上傳更新的原始碼
scp -r /path/to/updated/source  user@server:/opt/deploy/

# 2. 重新 build 並啟動（只會重建有變更的 image）
cd /opt/deploy/deployment-project/admin-node  # 或 game-node
docker compose up -d --build

# 3. 如果只改了設定檔（不需要重建 image）
docker compose restart backend
```

---

### Q9: 如何重置資料庫（全部從零開始）？

**A**:

```bash
# 停止並刪除所有容器和 volume（警告：會清除所有資料）
docker compose down -v

# 重新啟動（會重新執行 init SQL）
docker compose up -d --build
```

---

### Q10: `docker-entrypoint-initdb.d` 裡的 SQL 沒有執行？

**A**: PostgreSQL 的 `docker-entrypoint-initdb.d` **只在首次建立資料庫時執行**（即 `pg_data` volume 不存在的時候）。如果 volume 已經存在，init SQL 不會再跑。

解法：
- 刪除 volume 重建：`docker compose down -v && docker compose up -d`
- 或手動執行 SQL：`docker exec -i postgres psql -U postgres -d dcc_game < /path/to/sql`

---

### Q11: 自簽憑證環境下跨節點通訊怎麼處理？

**A**: 自簽憑證無法通過 Go 的 TLS 驗證（`x509: certificate signed by unknown authority`）。

**目前的解法**：跨節點服務間通訊改用 **VPC 內網 IP + HTTP**，不走 HTTPS。只有瀏覽器流量走 HTTPS（人可以手動接受憑證警告）。

- Backend → GameHub：`http://GAME_INTERNAL_IP:9643`（HTTP）
- GameHub → Backend：`http://ADMIN_INTERNAL_IP:9986`（HTTP）
- 瀏覽器 → nginx：`https://PUBLIC_IP`（HTTPS，自簽憑證）

這需要額外暴露 port 9986 和 9643（docker-compose 已設定），且兩台 VM 必須在同一 VPC 內網。

**正式環境**：使用 Let's Encrypt 等受信任 SSL 憑證後，跨節點可直接走 HTTPS，不需要暴露額外 port。詳見 Q26。

---

### Q12: 密碼是什麼？預設帳號密碼？

**A**:

| 帳號 | 密碼 | 用途 |
|------|------|------|
| `dccuser` | `12345678` | 管理後台登入（AES-256-CBC 加密） |
| `postgres` | setup.sh 設定的 `DB_PASS` | PostgreSQL 資料庫 |
| `dccuser` | `Dcc@12345` | DCC Tools MySQL |
| `root` | `RootPass123!` | DCC Tools MySQL root |

Redis 密碼在 `.env` 的 `REDIS_PASSWORD`。

---

### Q13: Windows 開發機上跑 Docker build 報錯（line endings）？

**A**: Windows 的 NTFS 檔案系統使用 `\r\n` 換行，Linux 容器使用 `\n`。如果 volume mount `.sh` 檔案到容器中，會出現 `\r: not found` 錯誤。

**我們的解法**：所有 shell script 都用 `RUN printf '...'` 直接寫進 Dockerfile，不依賴外部掛載的 `.sh` 檔案。

---

### Q14: 如何存取遠端 PostgreSQL 資料庫？

**A**: 資料庫不對外暴露。使用 SSH tunnel：

```bash
# Admin DB (dcc_game, dcc_order, dcc_chat, monitor)
ssh -L 5432:localhost:5432 user@ADMIN_IP
# 然後在本機用 psql 或 pgAdmin 連 localhost:5432

# Game DB (dayon_demo)
ssh -L 5433:localhost:5432 user@GAME_IP
# 然後在本機連 localhost:5433
```

注意：遠端部署中 postgres 沒有對外 port mapping（只有 Docker 內部網路可達），所以 SSH tunnel 方式無法直接使用。

**推薦方式**：SSH 到伺服器後用 docker exec：
```bash
docker exec -it admin-postgres psql -U postgres -d dcc_game
```

如需用 pgAdmin 等 GUI 工具，可以先在 docker-compose.yml 臨時加上 port mapping（`"5432:5432"`），用完再移除。

---

### Q15: `server_info` 表到底是做什麼的？各欄位什麼意思？

**A**: `server_info` 是整個系統的服務發現表，前端和後端都會讀取它來知道各服務的連線位址。

| code | 用途 | 誰讀取 | addresses 關鍵欄位 |
|------|------|--------|-------------------|
| `dev01` | GameHub 伺服器 | Backend（server-to-server） | `notification`: GameHub HTTP API URL |
| `chat` | 聊天服務 | 前端 JS（browser-facing） | `domain`: host:port, `scheme`: http/https |
| `api` | Backend API | 前端 JS（browser-facing） | `domain`: host:port, `scheme`: http/https |
| `monitor` | 監控服務 | 前端 JS（browser-facing） | `domain`: host:port, `scheme`: http/https |

**關鍵理解**：
- `dev01` 的 `notification` URL 是 Backend 內部用的，指向 GameHub 的 HTTP API
- `chat`/`api`/`monitor` 的 `domain` + `scheme` 是**瀏覽器**用的，必須是瀏覽器能連到的地址
- 遠端部署時，瀏覽器走 HTTPS 443，所以 domain 不需要帶 port（`https://ADMIN_IP` → 預設 443）
- 本地測試時，各服務暴露不同 port，所以 domain 要帶 port（`http://localhost:8896`）

---

### Q16: Backend 的 Agent Cache 是什麼？為什麼改了 DB 要重啟？

**A**: Backend 啟動時會把 `agent` 表的所有資料載入記憶體（`global.AgentCache`）。之後所有 agent 相關的操作（登入 IP 驗證、channelHandle API 驗證等）都讀 cache，不讀 DB。

所以如果你直接用 psql 修改了 agent 表的 `ip_whitelist`、`api_ip_whitelist`、`md5_key` 等欄位，必須重啟 Backend 才會生效：

```bash
docker compose restart backend
```

entrypoint 的設計已經考慮到這點 — 它在 Backend 第一次啟動前就用 psql 改好 DB，所以第二次啟動時 cache 會載入正確的值。

---

### Q17: 部署順序為什麼是 Game Node 先、Admin Node 後？

**A**: Backend 啟動時有個初始化流程：

1. 讀 `storage.GameKillDiveInfoReset` → 如果 `flag: true`
2. 從 `server_info.dev01.addresses.notification` 拿到 GameHub URL
3. 呼叫 `GET {gamehub_url}/getdefaultkilldiveinfo`
4. 把回傳的遊戲賠率資料寫入 `agent_game_ratio` 表
5. 如果 `agent_game_ratio` 為空 → 初始化失敗 → Backend crash

所以 GameHub 必須在 Backend 啟動前就 ready。entrypoint 有 wait loop（最多等 180 秒），但 GameHub 需要的時間包含 postgres init + game SQL + GameHub 本身啟動，所以建議先部署 Game Node。

**如果反了會怎樣**？Backend entrypoint 會在 wait loop 中等待，如果 180 秒內 GameHub ready 了就沒問題。超過 180 秒會跳過等待直接啟動，可能導致初始化失敗，需要再 restart 一次。

---

### Q18: 如何新增遊戲（不只是 Plinko）？

**A**: 需要：

1. **game-postgres**：在 `gamelist`、`gameinfo`、`lobbyinfo` 表中加入新遊戲資料
2. **admin-postgres**：在 `game` 表中加入遊戲條目，設定 `h5_link`、`server_info_code`
3. **admin-postgres**：在 `agent_game` 表中設定哪些代理可以看到這個遊戲
4. **遊戲客戶端**：部署新遊戲的靜態檔案到 game-client

---

### Q19: DCC Tools 測試工具怎麼使用？

**A**: DCC Tools 是一個 PHP 網頁工具，模擬第三方平台調用 channelHandle API 來建立玩家、開始遊戲。

存取方式：`https://ADMIN_IP/dcctools/`

使用前確認：
- DCC Tools 的 MySQL `agent` 表中的 `agent_id` 要和平台子代理的 PK 一致（預設是 5）
- `md5_key` 和 `aes_key` 也要和平台 agent 表同步
- DCC Tools MySQL `api_server` 表的 URL 指向 `http://backend:9986/channel/channelHandle?`（同一 Docker 網路內部通訊，不走 HTTPS）

---

### Q20: docker compose build 很慢怎麼辦？

**A**:

- Go 的 `go mod download` 和 Node 的 `npm install` 是最慢的步驟
- Dockerfile 已經把依賴下載和原始碼複製分開，利用 Docker layer cache
- **第一次 build** 一定慢（需要下載所有依賴）
- **之後的 build**，只要 `go.mod`/`package.json` 沒變，依賴層會 cache

如果需要更快：
1. 在本機 build image → push 到 registry → 伺服器上直接 pull
2. 或者在有更快網路的 CI 機器上 build

---

### Q21: game-postgres 啟動失敗，報 `value too long for type character varying(12)`？

**A**: gamelist.sql 和 gameinfo.sql 中的 `game_code` 欄位定義為 `varchar(12)`，但某些遊戲代碼超過 12 字元（例如 `pyrtreasureslot` = 15 字元）。

`setup.sh` 複製 SQL 時會自動用 `sed` 把 `varchar(12)` 改為 `varchar(50)`。如果你手動複製 SQL 檔，記得自己修正。

如果已經用舊的 SQL 建過 volume，需要：
```bash
docker compose down -v   # 刪除 volume
docker compose up -d     # 重新初始化
```

---

### Q22: `clean_init.sql` 不存在導致 postgres 啟動失敗？

**A**: Docker 掛載一個不存在的檔案時，會**自動建立一個同名資料夾**。PostgreSQL 嘗試執行這個「資料夾」就會報 `could not read from input file: Is a directory`。

`clean_init.sql` 是 `squash_db.sh` 的可選產物。在 `admin-node/docker-compose.yml` 中它已經被註解掉了。只有在跑過 `squash_db.sh` 後才取消註解。

本地測試的 `docker-compose.local.yml` 不掛載 `clean_init.sql`，Backend 會自己跑 migration。

---

### Q23: nginx.conf 有 HTTPS 和 HTTP 兩個版本？

**A**: 是的，有兩個版本的 nginx 設定：

| 檔案 | 用途 | SSL |
|------|------|-----|
| `admin-node/configs/nginx.conf` | 遠端部署 | HTTPS (443) |
| `configs/nginx-local.conf` | 本地測試 | HTTP (80) |

兩者的 location proxy 設定**完全相同**（/api, /channel, /chatservice.*, /monitor/, /dcctools/），差別只有 SSL 相關設定。

**如果改了其中一個的 proxy 設定，另一個也要同步修改。**

`Dockerfile.frontend` 的 COPY 會把 `admin-node/configs/nginx.conf` 寫入 image，但 `docker-compose.local.yml` 會用 volume mount 覆蓋成 `nginx-local.conf`。

---

### Q24: 自動產生的密碼導致 GameHub DB 連線失敗？

**A**: `openssl rand -base64` 會產生含 `+`、`/`、`=` 的密碼。GameHub 的 PostgreSQL 連線使用 URI 格式 (`postgres://user:password@host:port/db`)，密碼中的 `/` 會被當成路徑分隔符，導致解析錯誤：

```
parse "postgres://postgres:N2+gz5i8yDdzVEu/5HBZXQ==@postgres:5432/dayon_demo": invalid port
```

**解法**：`setup.sh` 已改用 `openssl rand -hex 12`，只產生 `0-9a-f` 字元。如果已經用了含特殊字元的密碼：

```bash
# 替換所有設定檔中的舊密碼
sed -i 's|舊密碼|新密碼|g' .env configs/GameHub.conf
# 刪除 volume 重建 DB
docker compose down -v
docker compose up -d
```

---

### Q25: Backend 啟動報 `vue_front/index.html: no such file or directory`？

**A**: Backend config 的 `load_front: true` 會讓 Backend 嘗試載入前端 HTML 模板。在遠端部署中，前端由 nginx 容器負責，Backend 不需要 serve 前端。

**解法**：`setup.sh` 已預設為 `false`。如果手動建立的 config.yml 還是 `true`：

```bash
sed -i 's/load_front: true/load_front: false/' configs/config.yml
docker compose restart backend
```

---

### Q26: 自簽憑證導致跨節點 HTTPS 通訊失敗（Go TLS 錯誤）— 技術細節

**A**:（另見 Q11 的簡要說明）Backend（Go 1.22）和 GameHub（Go 1.19）在跨節點 HTTPS 通訊時，會因為自簽憑證出現以下錯誤：

```
tls: failed to verify certificate: x509: certificate relies on legacy Common Name field, use SANs instead
```

或

```
x509: certificate signed by unknown authority
```

原因：
1. `openssl req -subj "/CN=IP"` 只設 CN，Go 1.15+ 要求 SAN
2. 自簽憑證不在受信任 CA 列表中

**推薦解法（GCP 同 VPC）**：跨節點服務間通訊改用**內網 IP + HTTP**，瀏覽器仍走 HTTPS。

```
瀏覽器 → https://PUBLIC_IP/api → admin nginx (HTTPS) → backend:9986
Backend → http://INTERNAL_IP:9643 → gamehub (HTTP, VPC 內網)
GameHub → http://INTERNAL_IP:9986 → backend (HTTP, VPC 內網)
```

需要的變更：
1. `admin-node/docker-compose.yml`：`GAMEHUB_URL=http://GAME_INTERNAL_IP:9643`，暴露 port 9986
2. `game-node/docker-compose.yml`：暴露 port 9643
3. `game-node/configs/GameHub.conf`：`SettlePlatform.DEV = http://ADMIN_INTERNAL_IP:9986/`

`setup.sh` 現在會詢問 Internal IP，自動生成正確的設定。

**正式環境解法**：使用 Let's Encrypt 等受信任 SSL 憑證，就可以直接走 HTTPS。

---

### Q27: `update_server_info.sql` 在 postgres 初始化時報 `relation does not exist`？

**A**: `docker-entrypoint-initdb.d` 裡的 SQL 在 postgres **首次初始化時**執行，但此時 `server_info`、`game`、`agent` 等表還不存在（由 Backend migration 建立）。

**解法**：這些 SQL（`update_server_info.sql`、`update_game_data.sql`）已從 postgres volume mount 中移除。Backend entrypoint 會在 migration 完成後自動執行這些更新。postgres 只需要 `init-extra-dbs.sql`（建立額外的資料庫）。

---

### Q28: GCP 部署時 setup.sh 要填什麼 Internal IP？

**A**: GCP Compute Engine VM 有兩個 IP：

| IP 類型 | 用途 | 範例 |
|---------|------|------|
| External IP (公網) | 瀏覽器存取、SSL 憑證 | 35.221.214.141 |
| Internal IP (VPC 內網) | 服務間通訊 | 10.140.0.4 |

查看 Internal IP：`gcloud compute instances list`（看 INTERNAL_IP 欄）

同一 VPC 的 VM 可以直接用 Internal IP 通訊（GCP 預設防火牆 `default-allow-internal` 允許所有內部流量）。不需要額外設定防火牆。

如果兩台伺服器不在同一內網（例如不同雲廠商），留空 Internal IP，setup.sh 會預設使用 Public IP（但需要正式 SSL 憑證）。

---

## 11. 目錄結構

```
deployment-project/
├── setup.sh                    # [Step 1] 生成所有設定檔
├── squash_db.sh                # [Step 2] 壓縮 DB migration（可選）
├── gcloud_firewall.sh          # [Step 3] GCP 防火牆指令參考
├── vm-init.sh                  # GCP VM 環境初始化（裝 Docker）
├── docker-compose.local.yml    # 本地測試用（全部服務跑在一台）
├── local-test.sh               # 本地測試輔助腳本
├── test-login.sh               # 登入測試腳本
├── DEPLOY_GUIDE.md             # 本文件（部署完整指南）
├── DEPLOYMENT_REPORT.md        # 客戶交付報告
├── build/                      # Dockerfiles（共用）
│   ├── Dockerfile.backend
│   ├── Dockerfile.frontend
│   ├── Dockerfile.gamehub
│   ├── Dockerfile.orderservice
│   ├── Dockerfile.chatservice
│   ├── Dockerfile.monitorservice
│   └── Dockerfile.dcctools
├── configs/                    # 本地測試用設定檔（靜態）
│   ├── config-local.yml        # Backend 本地設定
│   ├── orderservice-local.yml
│   ├── chatservice-local.yml
│   ├── monitorservice-local.yml
│   ├── GameHub.local.conf
│   ├── nginx-local.conf        # HTTP 反向代理（本地）
│   ├── game-client-nginx.conf
│   ├── game-client-config.json
│   ├── backend-entrypoint.sh
│   ├── init-extra-dbs.sql
│   └── dcctools-init-local.sql
├── admin-node/                 # 部署到 Admin Server
│   ├── docker-compose.yml
│   ├── .env                    # setup.sh 生成
│   ├── certs/                  # SSL 憑證
│   ├── configs/
│   │   ├── nginx.conf          # HTTPS 反向代理
│   │   ├── config.yml          # Backend（setup.sh 生成）
│   │   ├── orderservice.yml
│   │   ├── chatservice.yml
│   │   └── monitorservice.yml
│   ├── db-init/
│   │   ├── init-extra-dbs.sql  # 建立 dcc_order, dcc_chat, monitor
│   │   ├── dcctools-schema.sql # MySQL schema（setup.sh 複製）
│   │   └── dcctools-init.sql   # MySQL 資料修正
│   └── scripts/
│       ├── update_server_info.sql  # setup.sh 生成
│       └── update_game_data.sql    # setup.sh 生成
└── game-node/                  # 部署到 Game Server
    ├── docker-compose.yml
    ├── .env                    # setup.sh 生成
    ├── certs/                  # SSL 憑證
    ├── configs/
    │   ├── GameHub.conf        # setup.sh 生成
    │   ├── game-client-nginx.conf
    │   └── game-client-config.json  # setup.sh 生成
    ├── db-init/
    │   ├── gamelist.sql        # setup.sh 複製
    │   ├── gameinfo.sql
    │   └── lobbyinfo.sql
    └── client-dist/            # 遊戲客戶端靜態檔案
```

---

## 12. 本地測試

使用 `docker-compose.local.yml` 在單機上跑全部服務（不需要兩台伺服器）：

```bash
cd deployment-project
docker compose -f docker-compose.local.yml up --build
```

存取方式：
- 管理後台：`http://localhost/manager`
- 遊戲客戶端：`http://localhost:8080`
- DCC Tools：`http://localhost:8082`

本地測試與遠端部署的差異：
- HTTP（無 SSL）
- 所有服務 port 直接暴露（方便除錯）
- 設定檔在 `configs/` 目錄（`*-local.yml`、`nginx-local.conf`）
- `server_info` 的 domain 用 `localhost:PORT`（瀏覽器直連各服務）

---

## 13. 除錯指令速查

```bash
# ─── 查看服務狀態 ───
docker compose ps
docker compose logs -f <service_name>

# ─── Admin Node DB 查詢 ───
# server_info（服務連線資訊）
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT code, ip, addresses FROM server_info;"

# agent（代理設定，含 IP 白名單）
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT id, code, top_agent_id, ip_whitelist IS NOT NULL as has_wl, api_ip_whitelist IS NOT NULL as has_api_wl FROM agent;"

# storage（系統設定）
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT key, value FROM storage WHERE key LIKE 'Game%';"

# game（遊戲列表，含 h5_link）
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT id, name, h5_link, server_info_code FROM game;"

# agent_game_ratio（遊戲賠率，應有資料）
docker exec admin-postgres psql -U postgres -d dcc_game \
  -c "SELECT COUNT(*) FROM agent_game_ratio;"

# 注單記錄
docker exec admin-postgres psql -U postgres -d dcc_order \
  -c "SELECT bet_id, agent_id, username, game_id, ya_score, de_score FROM user_play_log ORDER BY create_time DESC LIMIT 10;"

# ─── Game Node DB 查詢 ───
docker exec game-postgres psql -U postgres -d dayon_demo \
  -c "SELECT * FROM gamelist;"

# ─── 測試 GameHub API ───
docker exec game-hub curl -s http://localhost:9643/ping
docker exec game-hub curl -s http://localhost:9643/getdefaultkilldiveinfo

# ─── 完全重置（清除所有資料） ───
docker compose down -v
docker compose up -d --build
```

---

## 14. 完整 Port 對照表

### 遠端部署（只暴露 80/443）

| 服務 | 容器內 Port | 對外 Port | 存取方式 |
|------|-----------|----------|---------|
| frontend (nginx) | 80, 443 | **80, 443** | `https://ADMIN_IP/` |
| backend | 9986 | **9986** (內網) | 透過 nginx `/api` 代理 + GameHub 內網直連 |
| orderservice | 9988 | 不暴露 | Docker 內部 |
| chatservice | 8896 | 不暴露 | 透過 nginx `/chatservice.*` 代理 |
| monitorservice | 17782, 17783 | 不暴露 | 透過 nginx `/monitor/` 代理 |
| dcctools | 8080 | 不暴露 | 透過 nginx `/dcctools/` 代理 |
| admin-postgres | 5432 | 不暴露 | `docker exec` 或 SSH tunnel |
| admin-redis | 6379 | 不暴露 | Docker 內部 |
| dcctools-mysql | 3306 | 不暴露 | Docker 內部 |
| game-client (nginx) | 80, 443 | **80, 443** | `https://GAME_IP/` |
| gamehub | 9643, 10101, 10201 | **9643** (內網) | 透過 nginx `/gamehub/`, `/ws` 代理 + Backend 內網直連 |
| game-postgres | 5432 | 不暴露 | `docker exec` 或 SSH tunnel |
| game-redis | 6379 | 不暴露 | Docker 內部 |

### 本地測試（所有 port 暴露方便除錯）

| 服務 | 容器內 Port | 本機 Port |
|------|-----------|----------|
| frontend | 80 | 80 |
| backend | 9986 | 9986 |
| orderservice | 9988 | 9988 |
| chatservice | 8896 | 8896 |
| monitorservice | 17782, 17783 | 17782, 17783 |
| dcctools | 8080 | 8082 |
| game-client | 80 | 8080 |
| gamehub | 9643, 10101, 10201 | 同 |
| admin-postgres | 5432 | 5432 |
| game-postgres | 5432 | 5433 |
| admin-redis | 6379 | 6379 |
| game-redis | 6379 | 6380 |
| dcctools-mysql | 3306 | 3307 |
