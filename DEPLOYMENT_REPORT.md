# DCC 遊戲平台 — GCP 佈署報告

**佈署日期**: 2026-02-08
**佈署環境**: Google Cloud Platform (GCP)
**區域**: asia-east1-b (台灣彰化)

---

## 1. 主機架構

本平台採用**雙節點架構**，將管理後台與遊戲服務分離部署於兩台 GCP Compute Engine VM：

| 節點 | 外部 IP | 內部 IP | 規格 | 作業系統 |
|------|---------|---------|------|----------|
| Admin Node (管理節點) | 35.221.214.141 | 10.140.0.4 | e2-medium (2 vCPU, 4GB RAM) | Debian 12 (bookworm) |
| Game Node (遊戲節點) | 107.167.184.252 | 10.140.0.5 | e2-medium (2 vCPU, 4GB RAM) | Debian 12 (bookworm) |

**網路架構**:
- 兩台 VM 位於同一 GCP VPC，透過內部 IP 進行服務間通訊 (HTTP)
- 對外透過 nginx 提供 HTTPS (443) 服務，使用自簽憑證
- GCP 防火牆規則允許 VPC 內部所有 TCP/UDP 流量

```
┌─────────────────────────────────────────────────────────────────┐
│                        瀏覽器 (使用者)                           │
│         https://35.221.214.141    https://107.167.184.252       │
└──────────┬──────────────────────────────────┬───────────────────┘
           │ HTTPS (443)                      │ HTTPS (443)
           ▼                                  ▼
┌─────────────────────┐          ┌─────────────────────┐
│   Admin Node        │          │   Game Node          │
│   (管理節點)         │  HTTP    │   (遊戲節點)         │
│                     │◄────────►│                      │
│  nginx (前端)       │ 內部IP   │  nginx (遊戲客戶端)  │
│  backend API        │ 9986↔    │  GameHub (遊戲伺服器)│
│  orderservice       │    9643  │  PostgreSQL (遊戲DB) │
│  chatservice        │          │  Redis (遊戲快取)    │
│  monitorservice     │          │                      │
│  dcctools           │          └─────────────────────┘
│  PostgreSQL (管理DB)│
│  Redis (管理快取)   │
│  MySQL (工具DB)     │
└─────────────────────┘
```

---

## 2. 服務清單與狀態

### Admin Node (管理節點) — 共 9 個服務

| 服務 | 容器名稱 | 埠號 | 狀態 | 說明 |
|------|----------|------|------|------|
| Frontend (nginx) | admin-frontend | 80, 443 | Healthy | 前端靜態檔案 + 反向代理 |
| Backend API | admin-backend | 9986 | Healthy | 後台管理 API |
| Order Service | orderservice | 9988 | Running | 訂單/交易服務 |
| Chat Service | chatservice | 8896 | Running | 即時聊天服務 |
| Monitor Service | monitorservice | 17782, 17783 | Running | 監控服務 |
| DCC Tools | dcctools | 8080 | Running | 同花順測試工具 |
| PostgreSQL | admin-postgres | 5432 | Healthy | 管理資料庫 (dcc_game, dcc_order, dcc_chat, monitor) |
| Redis | admin-redis | 6379 | Healthy | 快取與 Session |
| MySQL | dcctools-mysql | 3306 | Healthy | DCC Tools 專用資料庫 |

### Game Node (遊戲節點) — 共 4 個服務

| 服務 | 容器名稱 | 埠號 | 狀態 | 說明 |
|------|----------|------|------|------|
| Game Client (nginx) | game-client | 80, 443 | Healthy | 遊戲客戶端靜態檔案 + WebSocket 代理 |
| GameHub | game-hub | 9643 | Healthy | 遊戲邏輯伺服器 |
| PostgreSQL | game-postgres | 5432 | Healthy | 遊戲資料庫 (dayon_demo) |
| Redis | game-redis | 6379 | Healthy | 遊戲快取 |

---

## 3. 存取方式

### 3.1 管理後台

| 項目 | 值 |
|------|-----|
| 管理後台網址 | https://35.221.214.141/manager/ |
| 代理後台網址 | https://35.221.214.141/agent/ |
| 預設帳號 | dccuser |
| 預設密碼 | 12345678 |

> **注意**: 使用自簽憑證，瀏覽器會顯示安全性警告，需手動點擊「進階」→「繼續前往」。

### 3.2 遊戲客戶端

| 項目 | 值 |
|------|-----|
| 遊戲頁面 | https://107.167.184.252/ |

遊戲需透過後台的 `channelHandle` API 取得玩家 session 後才能進入遊戲，無法直接開啟遊戲頁面遊玩。正常流程為玩家從第三方平台導入。

### 3.3 DCC Tools (同花順測試工具)

| 項目 | 值 |
|------|-----|
| 測試工具網址 | https://35.221.214.141/dcctools/ |

---

## 4. 功能說明

### 4.1 管理後台 (Manager Panel)

管理後台提供完整的平台營運管理功能：

#### 運營管理
| 功能 | 說明 |
|------|------|
| 會員管理 | 查看/管理所有玩家帳號、餘額、狀態 |
| 存款管理 | 處理玩家存款申請與記錄 |
| 取款管理 | 處理玩家取款申請與審核 |
| 紅利設定 | 設定玩家紅利、優惠活動 |
| 活動管理 | 建立與管理行銷活動 |
| 返水設定 | 設定遊戲返水比例 |
| 公告管理 | 發布平台公告 |
| 信件管理 | 系統信件發送與管理 |
| 輪播圖管理 | 管理首頁輪播圖片 |

#### 系統管理
| 功能 | 說明 |
|------|------|
| 管理員帳號管理 | 建立/編輯管理員帳號與權限 |
| 角色管理 | 設定權限角色（RBAC 權限控制） |
| IP 白名單 | 管理允許存取的 IP 位址 |
| 操作日誌 | 查看所有管理員操作記錄 |
| 系統設定 | 平台基礎參數設定 |

#### 遊戲管理
| 功能 | 說明 |
|------|------|
| 遊戲列表 | 管理所有遊戲的上下架狀態 |
| 遊戲分類 | 設定遊戲分類與標籤 |
| 遊戲廠商管理 | 管理遊戲供應商資訊 |
| 遊戲設定 | 調整遊戲參數（賠率、限額等） |

#### 代理管理
| 功能 | 說明 |
|------|------|
| 代理帳號管理 | 建立/管理代理商帳號、費率設定 |

#### 報表管理
| 功能 | 說明 |
|------|------|
| 遊戲報表 | 各遊戲營收統計 |
| 玩家報表 | 個別玩家盈虧分析 |
| 代理報表 | 代理商業績統計 |
| 財務報表 | 平台整體財務數據 |
| 存取款報表 | 資金進出明細 |
| 返水報表 | 返水發放記錄 |
| 紅利報表 | 紅利發放記錄 |
| 佣金報表 | 佣金計算與發放 |

#### 風控功能
| 功能 | 說明 |
|------|------|
| 風控規則設定 | 設定風險控制觸發條件 |
| 風控告警 | 即時風險告警通知 |
| 異常行為偵測 | 偵測可疑玩家行為 |
| 黑名單管理 | 管理被封鎖的帳號/IP |
| 限額管理 | 設定各層級存取款限額 |
| 風控日誌 | 查看風控事件記錄 |
| 手動風控 | 人工介入處理風險事件 |
| KYC 審核 | 玩家身份驗證管理 |

#### Jackpot 管理
| 功能 | 說明 |
|------|------|
| Jackpot 池管理 | 管理獎池金額與累積規則 |
| Jackpot 設定 | 設定觸發條件與獎金分配 |
| Jackpot 歷史 | 查看開獎記錄 |
| Jackpot 報表 | 統計分析 |
| Jackpot 遊戲綁定 | 設定哪些遊戲參與 Jackpot |

### 4.2 代理後台 (Agent Panel)

代理商可透過獨立後台管理旗下業務：

| 功能 | 說明 |
|------|------|
| 儀表板 | 代理業績總覽 |
| 會員管理 | 管理旗下玩家 |
| 報表查詢 | 查看代理相關報表 |
| 佣金查詢 | 查看佣金結算明細 |
| 子代理管理 | 管理下級代理帳號 |
| 個人設定 | 修改密碼等個人資訊 |

### 4.3 即時通訊

- 後台內建即時聊天系統 (Chat Service)
- 支援管理員與玩家的即時對話
- WebSocket 長連線，訊息即時推送

### 4.4 監控服務

- 系統健康狀態監控 (Monitor Service)
- WebSocket 即時監控面板
- 異常告警通知

---

## 5. 技術架構

### 5.1 技術棧

| 層級 | 技術 |
|------|------|
| 前端 | Vue 3 + Vite + Element Plus |
| 後台 API | Go 1.22 + Gin Framework |
| 遊戲伺服器 | Go 1.19 + Gin + xorm |
| 訂單服務 | Go 1.18 |
| 聊天服務 | Go 1.18 + WebSocket |
| 監控服務 | Go 1.18 + WebSocket |
| 測試工具 | PHP 8 + nginx |
| 資料庫 | PostgreSQL 14 |
| 快取 | Redis (Alpine) |
| 容器化 | Docker + Docker Compose |
| 反向代理 | nginx (Alpine) |
| SSL | 自簽憑證 (測試環境) |

### 5.2 資料庫架構

**Admin Node PostgreSQL** 包含 4 個資料庫：
| 資料庫 | 用途 |
|--------|------|
| dcc_game | 主資料庫 (玩家、代理、遊戲、設定) |
| dcc_order | 訂單與交易記錄 |
| dcc_chat | 聊天訊息記錄 |
| monitor | 監控數據 |

**Game Node PostgreSQL** 包含 1 個資料庫：
| 資料庫 | 用途 |
|--------|------|
| dayon_demo | 遊戲運行數據 (遊戲列表、遊戲資訊、大廳設定) |

**Admin Node MySQL** 包含 1 個資料庫：
| 資料庫 | 用途 |
|--------|------|
| dcc | DCC Tools 測試工具數據 |

---

## 6. 啟動與維護

### 6.1 服務啟動

兩個節點各自使用 Docker Compose 管理，正常情況下服務已設定為 `restart: always`，VM 重啟後會自動恢復。

**手動啟動/停止**:

```bash
# Admin Node
cd /opt/deploy/admin-node
sudo docker compose up -d      # 啟動所有服務
sudo docker compose down        # 停止所有服務
sudo docker compose logs -f     # 查看即時日誌

# Game Node
cd /opt/deploy/game-node
sudo docker compose up -d
sudo docker compose down
sudo docker compose logs -f
```

**查看服務狀態**:
```bash
sudo docker compose ps
```

**查看特定服務日誌**:
```bash
sudo docker compose logs -f backend      # 後台 API 日誌
sudo docker compose logs -f gamehub      # 遊戲伺服器日誌
sudo docker compose logs -f frontend     # 前端 nginx 日誌
```

### 6.2 健康檢查

```bash
# Backend API
curl -k https://35.221.214.141/api/v1/health/health

# GameHub
curl http://10.140.0.5:9643/ping
```

### 6.3 資料庫備份

```bash
# Admin Node — 備份所有資料庫
sudo docker exec admin-postgres pg_dumpall -U postgres > admin_backup_$(date +%Y%m%d).sql

# Game Node — 備份遊戲資料庫
sudo docker exec game-postgres pg_dump -U postgres dayon_demo > game_backup_$(date +%Y%m%d).sql
```

### 6.4 重新佈署

如需重新佈署或更新版本：

```bash
# 1. SSH 進入對應 VM
gcloud compute ssh admin-node --zone=asia-east1-b

# 2. 拉取最新程式碼或上傳新檔案到 /opt/deploy

# 3. 重建並啟動
cd /opt/deploy/admin-node
sudo docker compose down
sudo docker compose build --no-cache
sudo docker compose up -d

# 4. 確認服務狀態
sudo docker compose ps
```

---

## 7. 注意事項

1. **SSL 憑證**: 目前使用自簽憑證，瀏覽器會顯示安全性警告。正式上線前建議更換為受信任的 SSL 憑證 (如 Let's Encrypt)。

2. **密碼安全**: 目前使用預設密碼，正式上線前請務必更改：
   - 管理員密碼 (目前: 12345678)
   - 資料庫密碼 (目前儲存在 .env 檔)
   - Redis 密碼

3. **IP 白名單**: 目前管理後台的 IP 白名單設為允許所有 IP (`*`)，正式上線前應限制為特定管理 IP。

4. **備份策略**: 建議設定定期自動備份 (cron job)，至少每日備份資料庫。

5. **監控**: 建議啟用 GCP Cloud Monitoring 監控 VM 資源使用率 (CPU、記憶體、磁碟)。

6. **擴展性**: 如需提升效能，可：
   - 垂直擴展：升級 VM 規格 (e2-standard-4 等)
   - 使用 GCP Cloud SQL 替代容器化 PostgreSQL (提供自動備份、高可用)

---

## 8. 聯絡資訊

如有任何問題，請聯繫技術團隊協助處理。

---

*本文件產生於 2026-02-08，反映當前佈署狀態。*
