# 安伴

面向胰腺癌晚期居家陪护的 **Flutter + Go** 应用。Flutter 负责会话内显示、加密、提醒和媒体；Go 提供账号、PostgreSQL 加密快照及 MinIO 加密附件服务。登录后自动读取云端，每次保存都需要服务器确认。

## 运行

根目录已提供 npm 启动入口，需要 Node.js 22.9+。没有 npm 依赖，无需执行 `npm install`。

```sh
npm run android   # 自动选择唯一已连接的 Android 手机或已启动的模拟器
npm run ios       # 自动选择唯一已连接的 iPhone 或已启动的 iOS 模拟器
npm run web       # 在 Chrome 中启动，端口 7357
npm run backend   # 读取根目录 .env，启动 Go 后端
```

手机或模拟器需先连接 / 启动。存在多个同平台设备时，用 `npm run android -- <设备ID>` 或 `npm run ios -- <设备ID>` 指定；`flutter devices` 可查看设备 ID，`flutter emulators --launch <模拟器ID>` 可启动模拟器。Web 端口被已有预览占用时，先停止旧预览服务。

首次启动后端前，将 `.env.example` 复制为 `.env` 并填入数据库与 MinIO 凭据。`.env` 已被 Git 忽略；现有终端环境变量优先于 `.env`。本次本地环境已配置，不要再覆盖现有 `.env`。

`npm run test:scripts` 验证启动脚本的设备选择及退出码传递，不会启动真实设备。

要求 Flutter 3.47 / Dart 3.13、Go 1.24 或更高版本。依赖版本已锁定在 `mobile/pubspec.lock`。

```sh
cd mobile
flutter pub get
flutter run -d chrome --web-port 7357
```

浏览器需使用 `localhost` 或 HTTPS，以便使用 WebCrypto。浏览器版供预览、记录与导出；后台提醒需安装 Android/iOS 应用。客户端不持久化照护资料或登录会话；重新打开后需登录并输入资料加密密码。

手机端：

```sh
cd mobile
flutter devices
flutter run -d <设备ID>
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Android 需完整 SDK、命令行工具及已确认的 SDK 许可证。iOS 需 Xcode，真机需要用户自己的开发者签名。工程默认的 Android release 签名仍是开发密钥，不能作为正式商店发布包。

生成完全本地的 Web 静态资源：

```sh
cd mobile
flutter build web --no-web-resources-cdn
python3 -m http.server 7357 --bind 127.0.0.1 --directory build/web
```

## Android 模拟器连接本机后端

`ANBAN_ADDR` 是 Go 后端的监听地址，例如 `127.0.0.1:8024`，不要填写 `http://`。`ANBAN_API_URL` 是客户端访问的完整URL；Android模拟器连接电脑使用 `http://10.0.2.2:8024`，不是模拟器自己的 `localhost`。

```dotenv
ANBAN_ADDR=127.0.0.1:8024
ANBAN_API_URL=http://10.0.2.2:8024
```

`npm run android`、`npm run ios`、`npm run web` 会读取根目录 `.env`，只将 `ANBAN_API_URL` 作为 Dart 编译参数传入；数据库和MinIO凭据不会作为编译参数打包。未填写API地址时，Android模拟器自动使用`10.0.2.2`，其他平台使用`localhost`。显式填写的地址优先；切换平台时按访问环境调整。

修改地址后停止原来的Flutter运行进程，再运行 `npm run android`；热重载不会改变 Dart 编译参数。真机需使用可访问的HTTPS后端地址。直接执行 `flutter run` 时，仍须手动传 `--dart-define=ANBAN_API_URL=...`。

### 本地后端启动与停止

`npm run backend`（或 `pnpm run backend`）默认使用8024端口。启动前通过`lsof`查找该端口的监听进程，先发送SIGTERM，未退出时再强制结束；此操作会结束占用该端口的其他程序。脚本收到Ctrl+C、SIGTERM或终端关闭信号时，清理本次启动的Go进程组，包括`go run`生成的子进程，释放端口。

该脚本支持macOS/Linux/WSL，需要`lsof`。操作系统强制结束脚本（SIGKILL）无法执行退出处理，下次启动会清理残留监听进程。Docker后台运行仍用`docker:down`停止容器；若端口由Docker占用，应先停止对应容器，避免Docker自动重启再次占用。

## Docker Compose 部署后端

安装 Docker Engine / Docker Desktop 和 Compose v2。项目根目录的 `.env` 填写实际 PostgreSQL、MinIO 配置（已有 `.env` 不要覆盖）。数据库和 MinIO 使用现有服务，Compose 只启动安伴后端。

```sh
npm run docker:build   # 构建镜像
npm run docker:up      # 后台运行
npm run docker:down    # 停止并移除容器，不删除外部数据库或MinIO数据
```

服务器没有 Node.js 时直接执行对应的 `docker compose build`、`docker compose up -d`、`docker compose down` 即可。修改代码后重新 build、up；修改 `.env` 后重新 up。

容器固定监听 `0.0.0.0:8024`，覆盖普通本地启动所用的 `ANBAN_ADDR`。宿主机默认发布到 `127.0.0.1:8024`，可供同机 HTTPS 反向代理使用；可用 `.env` 的 `ANBAN_BIND_IP`、`ANBAN_PORT` 修改宿主机绑定地址和端口。需要外部直接访问时设 `ANBAN_BIND_IP=0.0.0.0`；正式客户端仍需 HTTPS API 地址。数据库/MinIO 地址必须能从容器访问，容器里的 localhost 指容器自身。

镜像采用 Go 多阶段构建，运行时只包含二进制、CA证书和时区数据，以非root用户运行。构建上下文限定在 `backend/` 并使用白名单，`.env`、Git历史、客户端和本地数据不会进入镜像；实际凭据只在运行时注入，不写进 Dockerfile。

```sh
docker compose config --quiet  # 只校验，不打印展开后的凭据
docker compose ps
docker compose logs --tail=100 backend
```

健康检查使用 `/healthz`，表示后端进程响应正常；启动时会验证 PostgreSQL 和 MinIO 连接。容器异常退出后自动重启。

## 后端模块结构

```text
backend/
├── main.go                   # 读取配置、组装服务、启动HTTP
└── internal/
    ├── config/config.go      # 环境变量与默认值
    ├── storage/
    │   ├── storage.go        # PostgreSQL连接池、MinIO连接、选项初始化
    │   └── schema.sql        # 建表SQL，编译时内嵌
    └── server/
        ├── server.go         # 服务组装、CORS、会话鉴权、路由
        ├── auth.go           # 注册登录、密码、令牌、限流
        ├── vault.go          # 加密快照与版本冲突处理
        ├── files.go          # 附件上传下载和归属校验
        ├── options.go        # 健康选项读取
        ├── envelope.go       # 加密载荷结构与校验
        ├── http.go           # JSON请求解析、响应与错误
        └── server_test.go    # 验证与真实服务集成测试
```

依赖方向：入口使用配置并创建服务；服务使用存储模块建立连接，再把请求分发到各功能处理器。数据库查询保留在对应功能文件中，事务边界与原来一致。`npm run backend`、`go run .`、环境变量和API地址均不变；部署二进制无需额外复制`schema.sql`。

## 账号与 Go 后端

```sh
npm run backend
```

登录界面不再提供服务地址输入框；所有用户连接构建时指定的 `ANBAN_API_URL`。开发默认 `http://localhost:8024`，正式发布必须设置为部署好的安伴 Go 后端 HTTPS 地址（不是数据库或 MinIO 地址）。账号为 3–32 位字母、数字或下划线（不区分大小写），密码至少 6 个字符、最多 72 个 UTF-8 字节。服务端使用 bcrypt 哈希，随机会话有效期 30 天，仅保存会话令牌的 SHA-256 摘要；退出会撤销当前会话。客户端会话仅在进程内存中保存，不进入备份。

每个账号拥有独立的远端快照和附件。所有记录、患者档案和设置保存在 PostgreSQL 加密快照中，附件保存在 MinIO。客户端仅使用当前进程内存，不再创建本地照护数据库，也不持久化新登录会话和资料加密密码。登录时读取并解密云端资料；每次记录、编辑、删除、设置修改、备份恢复都自动上传，服务器确认后才更新界面。断网、会话失效或版本冲突时保存失败，不会伪装成本地保存成功。

登录需输入账号密码和**资料加密密码**。已有账号使用原云端备份密码；新账号设置至少 6 个字符。资料加密密码只在会话内存中使用，从不发送到后端，遗失无法恢复。新设备登录相同账号并输入相同资料加密密码即可读取已有云端资料。

旧版本机资料不会被静默删除。在「我的 → 数据与隐私」选择迁移当前账号旧资料或旧版离线资料，确认后上传到当前账号，替换当前云端快照；服务器保存成功后才清除对应旧版本机记录。已有云端资料时先手动导出备份。迁移失败保留旧资料。此迁移需在原来保存资料的设备/浏览器中操作。

| 环境变量 | 说明 |
| --- | --- |
| `ANBAN_ADDR` | 默认 `127.0.0.1:8024` |
| `ANBAN_ORIGINS` | 逗号分隔的浏览器 Origin 白名单 |
| `DATABASE_URL` | PostgreSQL 连接串，按实际环境配置 |
| `MINIO_ENDPOINT` | S3 API 地址，例如 `s3.example.com:9000`，不含协议或路径，不使用控制台端口 |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | 仅在后端设置 |
| `MINIO_USE_SSL` | 默认 `true`；当前 MinIO HTTP 服务设为 `false` |
| `MINIO_BUCKET` | `anban`，需预先创建为私有桶 |
| `TZ` | `Asia/Shanghai`；数据库时间使用 timestamptz |

启动会创建 `anban_users`、`anban_sessions`、`anban_vaults`、`anban_files` 表，不修改已有其他表。应使用专用数据库用户和私有桶权限。生产使用 HTTPS 反向代理安伴后端，并将请求体限制设为至少 40 MB、上传超时至少 120 秒；客户端仅允许 localhost/模拟器地址使用 HTTP。可通过 `flutter run --dart-define=ANBAN_API_URL=https://你的后端域名` 预填服务地址。当前 `.env` 的数据库连接为 `sslmode=prefer`，正式部署应配置证书并使用 `verify-full`，或使用可信私有网络。

### 同步与文件

登录时自动读取最新快照，修改自动上传。PostgreSQL 事务和版本号阻止并发覆盖；发生冲突后点“刷新云端资料”再重新提交。不同账号不共享资料。上传包括照护记录、回忆、病历、患者档案和所有应用设置，均在客户端加密；账号凭据不写入快照。单个附件最大 20 MB，当前快照附件合计最多 100 MB，快照最多 12 MB。未变更的附件复用云端对象，不随每次设置修改重复上传。备份恢复和迁移先完整验证附件，服务器成功保存后才替换会话数据。

客户端无持久化照护缓存。系统用药通知仍需保存提醒时间；原生视频播放器和录音过程可能使用临时文件，结束后清理。用户主动导出的 PDF、备份及原始照片属于用户文件，不会自动删除。退出清理会话数据和提醒；旧版本机数据库仅在成功迁移后清除。

附件以不可变随机对象保存至账号目录，下载经过后端鉴权，不公开 MinIO URL。重复上传、失败上传及删除快照后旧附件暂保留；尚未实现基于快照引用的垃圾回收，勿对桶设置任意过期规则以免损坏备份。旧版单文件家庭服务的快照不会自动导入 PostgreSQL，应通过旧客户端备份迁移。

### API

- `POST /api/v1/auth/register`、`POST /api/v1/auth/login`：`{username,password}`，返回 `{token,userId,username,expiresAt}`。
- `GET /api/v1/auth/me`、`POST /api/v1/auth/logout`：读取身份、撤销会话。
- `GET /api/v1/vault`：`{revision,updatedAt,data}` 和 `ETag`。
- `PUT /api/v1/vault`、`DELETE /api/v1/vault`：要求 `If-Match: "<revision>"`，初次为 `"0"`；冲突 409，缺失版本 428。
- `POST /api/v1/files`：上传加密 envelope，返回 `{id}`；`GET /api/v1/files/{id}`：仅所有者可下载。
- 上述除注册登录外均要求 `Authorization: Bearer <token>`；`GET /healthz` 为公开进程健康检查。
- 注册登录按来源 IP 限流，每分钟 10 次；当前为单进程限制，多实例部署需网关共享限流。反向代理下应在网关按真实 IP 限流，后端不信任任意转发头。

未实现邮箱验证、找回密码、跨账号家庭邀请；当前注册账号可直接使用自己的独立空间。

## 当前功能

- **首页**：化疗及维护行程、体重/大便/小便/疼痛/症状快捷记录、用餐与喝水安排。
- **健康记录**：所有记录保存明确的日期和时间；体重必填、体温/进食/说明可选；大便和小便情况必选且支持多选；小便可补充颜色、性状；保留疼痛与症状原有字段。
- **化疗及维护行程**：PICC护理、输液港护理、化疗。分类、上次及下次执行时间必填，下次必须晚于上次。可创建多个行程，详情可新增和修改执行记录，不提供删除。列表和提醒取上次执行时间最新的一条；补录更早历史不会倒退当前安排。
- **图片**：体重、大便、小便、行程及行程历史每条最多9张，可在保存前预览和移除；单张最多20 MB。全部图片进入加密快照引用，并上传MinIO。图片元数据与记录一起保存至PostgreSQL；一次快照附件总量上限100 MB。
- **我的**：患者基础档案、数据与隐私、使用偏好；提醒设置入口位于使用偏好中。保留大字/夜间模式、备份恢复和云端刷新。

陪伴菜单、旧护理内容、首页旧卡片，以及用药/体征/病历等旧记录入口已移除。为防止丢失已有数据，旧记录仍可随加密备份保存，不再显示在新页面，也不再安排旧用药提醒。

## 提醒规则

“我的 → 使用偏好 → 设置”分别控制用餐、喝水、PICC、输液港、化疗通知，初始均关闭，开启时请求系统通知权限。

| 项目 | 默认及规则 |
| --- | --- |
| 用餐 | 每天5次，每次30分钟，07:30开始、18:30前结束；开始时间均匀分布，最后一餐在结束时间前完成。支持1–12次、每餐5–180分钟，时段不足时拒绝保存。 |
| 喝水 | 用户填写同一天内的开始/结束时间，默认间隔30分钟；从开始时间起依次提醒，最后一次不晚于结束时间。 |
| 行程 | 三个分类分别设置提前天数（默认3天）及提前期间每天次数（默认1次）。提前期间默认09:00一次；多次在09:00–18:00均匀分布。执行当天在填写的执行时刻提醒；到期之后不继续提醒旧安排。 |

当前为**手机系统本地通知**，不是后台服务器推送。通知计划由云端资料生成；因iOS待处理通知上限，最多安排未来14天内最近60条，打开/回前台/修改计划后续排，设置页显示安排到的时间。频繁喝水提醒可能缩短覆盖时段，应定期打开应用。浏览器不支持后台系统提醒，实际通知仍需在Android/iOS真机验证；系统权限、省电和勿扰模式可能影响送达。

客户端不持久化照护资料库。系统通知需保存提醒时间；用户主动导出的文件不会自动删除。应用关闭后重新登录需要账号密码和资料加密密码。加密密码遗失无法恢复。

## 数据库可配置选项

后端启动创建并初始化 `anban_health_options`，已有配置不会被默认值覆盖。登录成功后客户端读取 `GET /api/v1/config/health-options`（需要Bearer会话）。无需修改或重新打包客户端即可通过数据库修改选项，重新登录后生效：

| key | 默认选项 |
| --- | --- |
| `stoolStatus` | 正常、未排便、黑便、血便、便秘、腹泻 |
| `urineStatus` | 正常、尿痛、血尿 |
| `urineColor` | 浅黄、淡黄色，类似淡啤酒色 |
| `urineAppearance` | 清澈、泡沫很少，静置一会泡沫消失、泡沫很多 |

例如由数据库管理员执行（JSON数组必须为非空字符串列表）：

```sql
UPDATE anban_health_options
SET options = '["正常", "未排便", "黑便", "血便", "便秘", "腹泻"]'::jsonb
WHERE key = 'stoolStatus';
```

已保存记录中的旧选项保持可见和可编辑，不会因为配置移除某项而丢失。配置编辑目前通过SQL完成，没有新增管理后台页面。

## 统一服务地址

目前还没有收到有效的安伴Go后端公网API地址；数据库与MinIO服务地址不能用于账号登录。部署时统一指定：

```sh
cd mobile
flutter run -d chrome --web-port 7357 --dart-define=ANBAN_API_URL=https://你的安伴后端域名
flutter build web --no-web-resources-cdn --dart-define=ANBAN_API_URL=https://你的安伴后端域名
```

同时将网页域名加入后端 `ANBAN_ORIGINS`，并重启后端加载新健康选项API。上线前需验证正式域名、HTTPS、真机通知权限及图像选择行为。

## 验证

```sh
cd backend
go test -race ./...
go vet ./...
```

```sh
cd mobile
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

`mobile/test/planning_test.dart` 覆盖用餐和喝水边界、行程更新、提前提醒及9图限制；`sync_test.dart` 覆盖9图云端往返及失败保护；`care_test.dart` 覆盖加密、登录入口及多尺寸页面。

远程集成验证（创建随机测试账号、上传测试密文，结束后清理测试数据）：

```sh
node --env-file=.env -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("go",["test","-race","-v","./..."],{cwd:"backend",env:{...process.env,ANBAN_INTEGRATION:"1"},stdio:"inherit"}); process.exit(r.status??1)'
```
