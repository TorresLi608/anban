# 安伴

面向胰腺癌晚期居家陪护的 **Flutter + Go** 应用。Flutter 负责会话内显示、加密、提醒和媒体；Go 提供账号、PostgreSQL 加密快照及 MinIO 加密附件服务。登录后自动读取云端，每次保存都需要服务器确认。

## 运行

根目录已提供 npm 启动入口，需要 Node.js 22.9+。移动端启动脚本无 npm 依赖；管理端首次运行需执行 `npm --prefix admin ci`。

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

## Android 检查更新与下载

### 应用图标

应用图标使用根目录 `logo.png`，已生成 Android 各密度启动图标与自适应图标、iOS AppIcon，以及 Flutter Web 图标。原图会按可见内容居中缩放，使用白色背景；iOS 图标不含透明通道。更新 `logo.png` 后，在根目录执行 `python3 scripts/generate-app-icons.py`（需要 Pillow）即可重新生成。图标属于原生打包资源，需要重新构建并安装应用，热重载不会更新桌面图标。

### 版本检查

Android 每次启动自动检查一次，发现更高的 `versionCode` 后显示新版说明，用户点击“前往下载”打开外部浏览器；下载完成后由用户按系统提示安装。登录页及“我的 → 使用偏好 → 检查更新”也可手动检查。自动检查失败保持安静，不影响登录和使用；iOS / Web 不显示此功能。

版本信息现在通过 Web 管理端维护，保存到 PostgreSQL 后立即生效。先按 [管理端说明](admin/README.md) 配置独立的管理端账号密码和公开下载域名，然后运行：

```sh
npm --prefix admin ci
npm run backend
# 另开终端
npm run admin
```

访问 `http://127.0.0.1:8025`。在“安卓版本”选择 APK，上传成功后自动生成公开下载地址，填写版本名称、递增的版本编号及更新说明，开启“向用户提示更新”并保存。APK 上限 300 MB，可查看上传进度及取消上传；上传完成不会自动发布，保存后才改变客户端的更新提示。

旧版 `.env` 中 `ANBAN_ANDROID_*` 配置仅在数据库首次初始化版本表时导入，之后以网页为准，重启不会覆盖网页保存的内容。关闭发布开关会暂停更新提示并保留版本信息。多人或多页面同时编辑时，旧页面保存会被拒绝，需重新载入后编辑。

发布流程：

1. 先安装包含本功能的客户端；此前没有检查更新代码的旧客户端需要手动下载安装一次。
2. 新版构建时递增版本编号，例如 `mobile/pubspec.yaml` 中 `version: 1.0.1+2`，或使用下列构建命令。`+2` 对应后端的 `VERSION_CODE=2`，`1.0.1` 对应 `VERSION_NAME`。
3. 在管理端上传 APK，核对自动生成的下载链接，再保存并发布。安装包存入 MinIO 的 `releases/android/` 目录，使用单独的公开下载接口，与私有照护附件隔离。已有下载链接保留，旧包不会自动删除。

```sh
cd mobile
flutter build apk --release --build-name=1.0.1 --build-number=2 --dart-define=ANBAN_API_URL=https://你的安伴后端域名
```

产物为 `mobile/build/app/outputs/flutter-apk/app-release.apk`。此流程使用通用 APK，不加 `--split-per-abi`；Flutter 拆分 APK 会改变实际 Android `versionCode`，服务端须填写产物中的实际编号。若之前分发过拆分包，新的通用包编号也必须高于所有已分发包，不能仅递增 `pubspec.yaml` 中较小的编号。

**覆盖安装必须保持包名和签名一致。** 项目目前 release 仍使用本机 debug 密钥；正式分发前应配置并妥善保存固定发布密钥，不能在已经分发后随意更换签名。系统可能要求允许浏览器“安装未知应用”。本功能不静默安装，也不提供 Flutter 代码热更新。

公开接口 `GET /api/v1/app/android-update` 返回 `{versionCode,versionName,downloadUrl,releaseNotes}`；未发布或暂停时返回 `204`，不缓存。先部署新版后端再发布客户端。可通过该接口确认发布信息。

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

## Docker Compose 部署后端与管理端

仅部署管理端可使用 `admin/compose.yaml`，账号配置、独立部署和修改密码步骤见 [管理端说明](admin/README.md)。管理端使用独立的环境变量账号密码，无需在 App 注册。

安装 Docker Engine / Docker Desktop 和 Compose v2。本地运行与 Docker 整套部署统一使用根目录的 [.env.example](.env.example) 模板：示例保存占位值，`.env` 保存实际配置，字段、顺序和分组一致。模板更新后，已有 `.env` 不会自动同步，请按示例补齐缺项并保留原有值。

首次使用时执行，再编辑 `.env` 中的 PostgreSQL、MinIO 配置（已有文件不会覆盖）：

```sh
cp -n .env.example .env
chmod 600 .env
docker compose config --quiet  # 填好配置后校验，不打印展开后的凭据
```

数据库和 MinIO 使用现有服务。Compose 启动 Go 后端与 Next.js 管理端，宿主机端口分别为 `8024`、`8025`，默认绑定 `127.0.0.1`，生产请经 HTTPS 反向代理访问。登录管理端前填写 `ANBAN_ADMIN_USERNAME`（默认 `admin`）和 `ANBAN_ADMIN_PASSWORD`（无默认密码，留空禁用登录），发布 APK 前填写 `ANBAN_PUBLIC_URL`。修改凭据后执行 `docker compose up -d backend`，所有管理端会话失效，App 账号不受影响。旧 `ANBAN_ADMIN_USERS` 授权方式已停用，详见 [管理端说明](admin/README.md)。

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
        ├── admin.go          # 管理员版本发布、健康选项写入与并发保护
        ├── apks.go           # APK 上传和公开下载
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

启动会创建安伴账号、会话、快照、附件和健康选项表，以及 `anban_android_release`、`anban_apks` 管理表，不修改其他业务表。应使用专用数据库用户和私有桶权限。生产使用 HTTPS 反向代理安伴后端，并将请求体限制设为至少 40 MB、上传超时至少 120 秒；APK 上传另外需要至少 301 MB 请求体与 600 秒超时（见管理端说明）。客户端仅允许 localhost/模拟器地址使用 HTTP。可通过 `flutter run --dart-define=ANBAN_API_URL=https://你的后端域名` 预填服务地址。当前 `.env` 的数据库连接为 `sslmode=prefer`，正式部署应配置证书并使用 `verify-full`，或使用可信私有网络。

### 同步与文件

登录时自动读取最新快照，修改自动上传。PostgreSQL 事务和版本号阻止并发覆盖；发生冲突后点“刷新云端资料”再重新提交。不同账号不共享资料。上传包括照护记录、回忆、病历、患者档案和所有应用设置，均在客户端加密；账号凭据不写入快照。医疗档案单文件最大 200 MB，不设文件夹内或每批上传数量上限，取消了原先的附件合计 100 MB 限制。新文件按 4 MB 分块加密上传，各块使用独立随机 nonce 并认证文件标识和块序号；资料目录过大时也分块保存，根快照仍满足后端请求限制。登录只下载目录，预览和导出时才读取原件，未变更文件不会重复下载或上传。少量预览只在进程内进行有界缓存。旧格式附件仍能读取；备份恢复和迁移在服务器确认后才替换会话数据。

客户端无持久化照护缓存。系统用药通知仍需保存提醒时间；原生视频播放器和录音过程可能使用临时文件，结束后清理。用户主动导出的 PDF、备份及原始照片属于用户文件，不会自动删除。退出清理会话数据和提醒；旧版本机数据库仅在成功迁移后清除。

附件以不可变随机对象保存至账号目录，下载经过后端鉴权，不公开 MinIO URL。重复上传、失败上传及删除快照后旧附件暂保留；尚未实现基于快照引用的垃圾回收，勿对桶设置任意过期规则以免损坏备份。旧版单文件家庭服务的快照不会自动导入 PostgreSQL，应通过旧客户端备份迁移。

### API

- `POST /api/v1/auth/register`、`POST /api/v1/auth/login`：`{username,password}`，返回 `{token,userId,username,expiresAt}`。
- `GET /api/v1/auth/me`、`POST /api/v1/auth/logout`：读取身份、撤销会话。
- `GET /api/v1/vault`：`{revision,updatedAt,data}` 和 `ETag`。
- `PUT /api/v1/vault`、`DELETE /api/v1/vault`：要求 `If-Match: "<revision>"`，初次为 `"0"`；冲突 409，缺失版本 428。
- `POST /api/v1/files`：上传加密 envelope，返回 `{id}`；`GET /api/v1/files/{id}`：仅所有者可下载。
- 上述除注册登录外均要求 `Authorization: Bearer <token>`；`GET /healthz` 为公开进程健康检查，`GET /api/v1/app/android-update` 为公开安卓版本信息，`GET /api/v1/app/android-apk/{id}.apk` 为公开 APK 下载（支持 Range）。
- 注册登录按来源 IP 限流，每分钟 10 次；当前为单进程限制，多实例部署需网关共享限流。反向代理下应在网关按真实 IP 限流，后端不信任任意转发头。

未实现邮箱验证、找回密码、跨账号家庭邀请；当前注册账号可直接使用自己的独立空间。

## 当前功能

- **首页**：化疗及维护行程、体重/大便/小便/疼痛/症状快捷记录、用餐与喝水安排。
- **健康记录**：所有记录保存明确的日期和时间；体重必填、体温/进食/说明可选；大便和小便情况必选且支持多选；小便可补充颜色、性状；保留疼痛与症状原有字段。
- **化疗及维护行程**：PICC护理、输液港护理、化疗。分类、上次及下次执行时间必填，下次必须晚于上次。可创建多个行程，详情可新增和修改执行记录，不提供删除。列表和提醒取上次执行时间最新的一条；补录更早历史不会倒退当前安排。
- **图片**：体重、大便、小便、行程及行程历史每条最多9张，可在保存前预览和移除；单张最多20 MB。全部图片进入加密快照引用，并上传MinIO。图片元数据与记录一起保存至PostgreSQL，不再限制附件合计 100 MB。
- **医疗资料**：档案、看诊、医嘱三个页签。自定义多级文件夹，支持批量上传、搜索、移动、重命名、原件预览/导出；门诊和住院记录可关联文件或整个文件夹；医嘱可快速记录、关联看诊和置顶。
- **我的**：患者基础档案、数据与隐私、使用偏好；提醒设置入口位于使用偏好中。保留大字/夜间模式、备份恢复和云端刷新。

陪伴菜单、旧护理内容、首页旧卡片，以及用药/体征等旧记录入口已移除；原有病历会在“医疗资料 → 档案”根目录显示。为防止丢失已有数据，旧记录仍可随加密备份保存，不再显示在新页面，也不再安排旧用药提醒。

## 医疗资料使用方式

- **档案**：在“医疗资料 → 档案”新建文件夹，进入后可继续创建子文件夹或批量选择文件。支持病历、CT/MRI 报告、图片、视频、PDF、DICOM/压缩包等原文件；格式不受上传白名单限制。图片、PDF 和设备可解码的视频可内置预览，其他格式导出后用相应软件打开。单文件 200 MB；保存按文件依次完成，取消会在当前文件完成后停止，失败会明确提示已保存数量，已完成文件不会丢失。
- **整理**：文件和文件夹可重命名、移动；禁止将文件夹移到自己或后代。非空文件夹不能直接删除，防止误删整组资料。删除文件/空文件夹会解除看诊中的相关关联，保留看诊正文。
- **看诊**：记录门诊/住院类型、医院/科室/医生、看诊或入院时间、原因、诊疗结果/住院经过、后续安排和可选出院时间。关联可选择单份档案或整个文件夹；关联文件夹包含其子文件夹以及后续放入的档案。详情可直接打开关联资料并添加本次医嘱。
- **医嘱**：首页“记医嘱”或医疗资料页均可快速录入。内容必填，其他信息可稍后完善，可关联看诊并置顶。这里只记录用户填写的医嘱，不生成治疗方案。
- **导出**：看诊/医嘱可导出中文 PDF；档案文件夹及看诊关联原件可导出 ZIP，包含 PDF 索引、目录 JSON 和原文件，保留目录层级。同名文件带标识避免覆盖。大批量资料按约 64 MB 目标分成多个独立 ZIP；单个大文件单独成包，逐包选择保存，取消不会继续读取余下文件。导出文件为未加密副本，应由用户妥善保管。

新客户端兼容读取旧资料和旧加密备份。保存后使用新版资料格式（v2），旧客户端不能读取新的目录/关联信息；请统一升级使用此账号的设备。大量档案优先使用上述分卷导出，原有全量加密备份会读取全部原件，受设备可用内存限制。文件数量不设业务上限，但仍受服务器空间与设备资源限制。

## 提醒规则

“我的 → 使用偏好 → 设置”分别控制用餐、喝水、PICC、输液港、化疗通知，初始均关闭，开启时请求系统通知权限。

| 项目 | 默认及规则 |
| --- | --- |
| 用餐 | 每天5次，每次30分钟，07:30开始、18:30前结束；开始时间均匀分布，最后一餐在结束时间前完成。支持1–12次、每餐5–180分钟，时段不足时拒绝保存。 |
| 喝水 | 用户填写同一天内的开始/结束时间，默认间隔30分钟；从开始时间起依次提醒，最后一次不晚于结束时间。 |
| 行程 | 三个分类分别设置提前天数（默认3天）及提前期间每天次数（默认1次）。提前期间默认09:00一次；多次在09:00–18:00均匀分布。执行当天在填写的执行时刻提醒；到期之后不继续提醒旧安排。 |

当前为**手机系统本地通知**，不是后台服务器推送。通知计划由云端资料生成；Android 的用餐和喝水按每天循环排程，不再受旧版 60 条队列限制；一次计划为行程保留空间，总计不超过 450 个系统闹钟。相同时刻的用餐和喝水合为一条包含两种内容的提醒，避免通知提示互相覆盖。iOS 最多保留 60 条，在类型间分配名额，避免喝水占满队列；打开/回前台/修改计划后续排，前台接近某类覆盖末端时也会续排。设置页显示各类下次时间，提供用餐/喝水测试通知及系统通知设置入口，并提示关闭的通知渠道。打开登录页不会清空已有提醒，重排只取消未触发的通知；明确退出账号会清理提醒。浏览器不支持后台系统提醒，实际通知仍需在Android/iOS真机验证；系统权限、省电和勿扰模式可能影响送达。

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

已保存记录中的旧选项保持可见和可编辑，不会因为配置移除某项而丢失。日常维护可在管理端“健康选项”页面编辑，每行一个选项，每组 1–50 项，每项最多 100 字。保存后用户下次登录读取新选项；旧记录中的已选内容保持可见。仍可通过 SQL 维护，管理端也能检测并发 SQL 修改。

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
npm run admin:lint
npm run admin:build
```

管理端真实数据库/MinIO 隔离测试参见 `admin/README.md`。

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

`mobile/test/medical_test.dart` 覆盖目录关系、看诊/医嘱、PDF/ZIP 和多尺寸界面；`attachment_sync_test.dart` 覆盖分块认证、按需读取与旧附件兼容。`mobile/test/planning_test.dart` 覆盖用餐和喝水边界、行程更新、提前提醒及9图限制；`sync_test.dart` 覆盖9图云端往返及失败保护；`care_test.dart` 覆盖加密、登录入口及多尺寸页面。

远程集成验证（创建随机测试账号、上传测试密文，结束后清理测试数据）：

```sh
node --env-file=.env -e 'const {spawnSync}=require("node:child_process"); const r=spawnSync("go",["test","-race","-v","./..."],{cwd:"backend",env:{...process.env,ANBAN_INTEGRATION:"1"},stdio:"inherit"}); process.exit(r.status??1)'
```
