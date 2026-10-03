# 安伴管理端

Next.js App Router + TypeScript + Tailwind CSS v4 + shadcn/ui。管理员登录、APK 上传与版本发布、健康选项维护、修改密码均接入现有 Go 服务。

## 默认账号和密码

**没有内置默认账号或默认密码。** 账号为 Go 后端 `ANBAN_ADMIN_USERS` 指定的已注册安伴账号，密码为该账号注册时设置的登录密码。示例配置和测试账号都不是生产登录凭据。

首次使用按下方步骤注册并授权一次；以后可在“账号安全”修改密码。

## 首次配置

1. 先通过安伴客户端注册一个账号，确认能够登录。管理端不开放注册。
2. 在项目根目录现有 `.env` 增加配置，不要覆盖数据库与 MinIO 配置：

```dotenv
ANBAN_ADMIN_USERS=你的已注册账号
ANBAN_ADMIN_API_URL=http://127.0.0.1:8024
ANBAN_PUBLIC_URL=https://你的Go后端域名
ANBAN_ADMIN_PORT=7358
```

`ANBAN_ADMIN_USERS` 可用英文逗号分隔多个账号（不区分大小写）。留空时无人有管理权限；不存在的账号会导致后端启动失败，避免他人抢先注册该名称后获得管理权限。修改授权名单需重启后端。日常版本/选项维护无需重启。

`ANBAN_PUBLIC_URL` 是手机和浏览器均可访问的 **Go 后端 HTTPS 域名**，不是管理端域名，也不是 MinIO 控制台。不含路径或查询参数。APK 上传后生成 `${ANBAN_PUBLIC_URL}/api/v1/app/android-apk/<随机ID>.apk`。未配置时可以登录和编辑健康选项，但不能上传 APK。

`ANBAN_ADMIN_API_URL` 仅供 Next.js 服务器连接 Go 后端，不会发送到浏览器。Docker Compose 内部自动使用 `http://backend:8024`，无需额外配置 CORS。管理员会话保存在 HttpOnly、SameSite=Strict Cookie 中，有效期 8 小时；生产 Cookie 使用 Secure，管理端必须经 HTTPS 访问。

## 本地运行

在项目根目录执行：

```sh
npm --prefix admin ci
npm run backend
# 另开终端
npm run admin
```

打开 `http://127.0.0.1:7358`，使用已授权的安伴账号和账号密码登录，不需要资料加密密码。`npm run admin` 读取根目录 `.env`，使用开发模式监听本机。`npm run web` 仍为 Flutter Web 预览，与管理端不同。

## 发布安卓版本

1. 使用固定签名构建 APK，保持包名，递增 `versionCode`。
2. 在“安卓版本”选择 `anban.apk`（最大 300 MB）。页面显示上传进度，成功后自动回填下载地址。
3. 填写与 APK 对应的版本名称和版本编号，填写更新说明（可选），开启“向用户提示更新”，点击“保存并发布”。
4. 客户端下次检查更新时读取新版本。关闭开关并保存可暂停提示。

上传只保存文件，不自动发布。版本名称/编号需要按构建参数填写，本版不解析 APK 内的二进制 Manifest。后端检查 APK ZIP 结构及根目录 `AndroidManifest.xml`，不执行或解压安装包。新旧包的签名一致性仍由构建与 Android 安装器保证。

安装包保存在现有 MinIO 私有桶的 `releases/android/` 目录，下载经过 Go 服务的独立公开接口，支持 Range 和 HEAD。普通账号无法上传；公开链接只用于 APK，不会公开照护附件。每次上传生成新对象，不覆盖旧包。已上传但未发布的包及历史包暂时保留，不会自动清理，以免破坏已有下载链接。改动公开域名后，新上传使用新域名；旧链接应保留域名或通过代理转发。

旧 `.env` 的 `ANBAN_ANDROID_*` 字段仅用于版本表第一次初始化。之后以数据库为准，不会在重启时覆盖网页内容。保存带版本校验，多页面编辑冲突会提示重新载入，表单内容不会被失败响应清空。

## 健康选项

四组可编辑：大便情况、小便情况、小便颜色、小便性状。每行一项，最多 50 项，每项最多 100 字，不允许重复。保存一次原子更新全部四组，用户下次登录生效。移除选项不改变已保存的健康记录。管理端不读取、解密或展示患者资料。

## 修改密码

进入“账号安全”，输入当前密码、新密码及确认密码。新密码至少 6 个字符、最多 72 个 UTF-8 字节，且不能与当前密码相同。

修改成功后自动返回登录页，该账号的所有管理端和手机客户端会话都被撤销，需使用新密码重新登录。账号密码与资料加密密码是两件事：修改登录密码不会改变资料加密密码，也不会重新加密或删除照护资料。密码使用 bcrypt 哈希保存；密码更新和会话撤销在同一数据库事务中完成。

## 部署

以下两种方式任选一种，不要让两个管理端容器占用同一宿主机端口。前端使用非 root 用户、Next.js standalone 产物和健康检查；密码等账号数据保存在现有 Go 后端数据库中。

### 与 Go 后端一起部署

在项目根目录配置 `.env` 后执行：

```sh
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 admin
```

根目录 `compose.yaml` 同时启动后端和管理端，管理端通过容器网络访问 `http://backend:8024`。默认宿主机端口 7358，可通过根目录 `.env` 的 `ANBAN_ADMIN_PORT` 修改。

### 只部署管理端

Go 后端已部署时，可独立使用 `admin/compose.yaml`：

```sh
cd admin
cp .env.example .env  # 仅首次执行；已有 .env 时不要覆盖
# 编辑 .env 中的 ANBAN_ADMIN_API_URL，填写容器能访问的 Go 后端地址
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 admin
```

例如 `ANBAN_ADMIN_API_URL=https://api.example.com`。此地址必须能从管理端容器访问；`127.0.0.1` 指向管理端容器自身，不能用于访问容器外的 Go 服务。`ANBAN_ADMIN_USERS`、数据库/MinIO 配置、`ANBAN_PUBLIC_URL` 均配置在 **Go 后端**，不放在管理端容器中。

独立部署默认绑定宿主机 `127.0.0.1:7358`；`ANBAN_ADMIN_BIND_IP` 和 `ANBAN_ADMIN_PORT` 分别控制绑定地址和端口。生产应通过 HTTPS 反向代理访问，否则浏览器不会发送 Secure 会话 Cookie。需要远程代理直接连接端口时，可将绑定地址设为 `0.0.0.0` 并在网络侧限制访问。

反向代理需要：

- 管理端域名转发至 `127.0.0.1:7358`；Go 后端域名转发至 `127.0.0.1:8024`。
- 保留正确的 `Host` / `X-Forwarded-Host` / `X-Forwarded-Proto`。不要开放任意 Server Action 跨域来源。
- 管理端 `/api/apk` 与 Go `/api/v1/admin/apks` 的请求体限制至少 **301 MB**，读写超时至少 **600 秒**（例如 Nginx `client_max_body_size 301m`、`proxy_read_timeout 600s`、`proxy_send_timeout 600s`）。建议关闭上传代理缓冲。公开下载接口也应允许长下载。
- 后端上传使用临时文件，Compose 已给只读后端提供 384 MB `/tmp`。较多并发上传时增加临时空间；当前界面一次上传一个包。

也可独立运行生产管理端：

```sh
npm run admin:build
HOSTNAME=127.0.0.1 PORT=7358 node --env-file-if-exists=.env admin/.next/standalone/server.js
```

构建不需要在线字体服务，也不需要运行中的数据库。构建上下文排除 `.env`、测试文件和本机安装包；数据库/MinIO 凭据仅传给 Go 后端。

## 验证

```sh
npm run admin:lint
npm run admin:build
cd backend
go test -race ./...
go vet ./...
```

真实 PostgreSQL / MinIO 集成测试（在项目根目录）：

```sh
node --env-file=.env -e 'const {spawnSync}=require("node:child_process");const r=spawnSync("go",["test","-race","-v","./internal/server","-run","TestAdminIntegration"],{cwd:"backend",env:{...process.env,ANBAN_ADMIN_INTEGRATION:"1"},stdio:"inherit"});process.exit(r.status??1)'
```

测试在随机命名的独立 PostgreSQL schema 中运行，测试结束删除该 schema 及其中登记的测试 APK 对象，不改动业务资料。数据库账号需要创建 schema 的权限。覆盖管理员权限、改密校验、旧密码失效、全部账号会话撤销、其他账号不受影响、上传/下载、发布/暂停、并发编辑与重启保留配置。
