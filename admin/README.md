# 安伴管理端

Next.js App Router + TypeScript + Tailwind CSS v4 + shadcn/ui。管理员登录、APK 上传与版本发布、健康选项维护均接入现有 Go 服务。管理端账号密码通过 Go 后端环境变量配置。

## 管理端账号和密码

管理端使用独立账号，无需在安伴 App 注册，也不会创建或修改 App 账号。默认账号名为 `admin`，**没有默认密码**；密码留空时禁用管理端登录。

在项目根目录的 `.env` 中配置（已有文件按项修改，不要覆盖数据库和 MinIO 配置）：

```dotenv
ANBAN_ADMIN_USERNAME=admin
ANBAN_ADMIN_PASSWORD='替换为你自己的管理端密码'
ANBAN_ADMIN_API_URL=http://127.0.0.1:8024
ANBAN_PUBLIC_URL=https://你的Go后端域名
ANBAN_ADMIN_ADDR=127.0.0.1:8025
```

账号支持 3–32 位字母、数字或下划线，不区分大小写；密码至少 6 个字符、最多 72 个 UTF-8 字节，保留大小写与首尾空格。密码可用单引号包裹，避免 `$` 等字符被 Compose 展开。账号和密码只配置在 Go 后端，登录页不会预填或展示密码。

旧 `ANBAN_ADMIN_USERS` 授权方式已停用。升级后填写上述两个新变量，并重新构建、启动后端与管理端：`docker compose up -d --build`。原 App 账号、密码和资料保留，原 App 会话无法访问管理端。

`ANBAN_PUBLIC_URL` 是手机和浏览器均可访问的 **Go 后端 HTTPS 域名**，不是管理端域名，也不是 MinIO 控制台。不含路径或查询参数。APK 上传后生成 `${ANBAN_PUBLIC_URL}/api/v1/app/android-apk/<随机ID>.apk`。未配置时可以登录和编辑健康选项，但不能上传 APK。

`ANBAN_ADMIN_API_URL` 仅供 Next.js 服务器连接 Go 后端，不会发送到浏览器。Docker Compose 内部自动使用 `http://backend:8024`，无需额外配置 CORS。浏览器令牌保存在 HttpOnly、SameSite=Strict Cookie 中，有效期 8 小时；生产 Cookie 使用 Secure，管理端必须经 HTTPS 访问。Go 后端只保存密码的 bcrypt 哈希和会话令牌的 SHA-256 摘要，管理端会话存于进程内存，退出或重启后端后失效。当前适用于单个 Go 后端实例；扩展多实例前需改用共享会话存储。

## 本地运行

在项目根目录执行：

```sh
npm --prefix admin ci
npm run backend
# 另开终端
npm run admin
```

默认打开 `http://127.0.0.1:8025`，使用 `ANBAN_ADMIN_USERNAME` 和 `ANBAN_ADMIN_PASSWORD` 配置的管理端账号密码登录。`npm run admin` 读取根目录 `.env`，按 `ANBAN_ADMIN_ADDR` 的 IP 和端口启动开发服务。`npm run web` 仍为 Flutter Web 预览，与管理端不同。

## 发布安卓版本

1. 使用固定签名构建 APK，保持包名，递增 `versionCode`。
2. 在“安卓版本”选择 `anban.apk`（最大 300 MB）。页面显示上传进度，成功后自动回填下载地址。
3. 填写与 APK 对应的版本名称和版本编号，填写更新说明（可选），开启“向用户提示更新”，点击“保存并发布”。
4. 客户端下次检查更新时读取新版本。关闭开关并保存可暂停提示。

上传只保存文件，不自动发布。版本名称/编号需要按构建参数填写，本版不解析 APK 内的二进制 Manifest。后端检查 APK ZIP 结构及根目录 `AndroidManifest.xml`，不执行或解压安装包。新旧包的签名一致性仍由构建与 Android 安装器保证。

安装包保存在现有 MinIO 私有桶的 `releases/android/` 目录，下载经过 Go 服务的独立公开接口，支持 Range 和 HEAD。普通账号无法上传；公开链接只用于 APK，不会公开照护附件。每次上传生成新对象，不覆盖旧包。已上传但未发布的包及历史包暂时保留，不会自动清理，以免破坏已有下载链接。改动公开域名后，新上传使用新域名；旧链接应保留域名或通过代理转发。

安卓版本通过管理端发布，无需在 `.env` 中填写版本信息。版本以数据库为准，不会在重启时覆盖网页内容。保存带版本校验，多页面编辑冲突会提示重新载入，表单内容不会被失败响应清空。

## 健康选项

四组可编辑：大便情况、小便情况、小便颜色、小便性状。每行一项，最多 50 项，每项最多 100 字，不允许重复。保存一次原子更新全部四组，用户下次登录生效。移除选项不改变已保存的健康记录。管理端不读取、解密或展示患者资料。

## 修改账号或密码

修改 Go 后端 `.env` 中的 `ANBAN_ADMIN_USERNAME` 或 `ANBAN_ADMIN_PASSWORD` 后执行：

```sh
docker compose up -d backend
```

本地通过 `npm run backend` 启动时，停止后重新运行即可。环境变量是管理端凭据的唯一来源，「账号安全」页提供修改说明。重启后全部管理端会话失效，使用新凭据重新登录；App 账号密码和会话不受影响。将密码清空并重新启动后端可禁用管理端登录。

## 部署

以下两种方式任选一种，不要让两个管理端容器占用同一宿主机端口。前端使用非 root 用户、Next.js standalone 产物和健康检查；管理端凭据由 Go 后端环境变量提供，业务数据保存在现有 PostgreSQL 和 MinIO 中。

### 与 Go 后端一起部署

在项目根目录配置 `.env` 后执行：

```sh
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 admin
```

根目录 `compose.yaml` 同时启动后端和管理端，管理端通过容器网络访问 `http://backend:8024`。默认宿主机地址 `127.0.0.1:8025`，可通过根目录 `.env` 的 `ANBAN_ADMIN_ADDR` 修改。

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

例如 `ANBAN_ADMIN_API_URL=https://api.example.com`。此地址必须能从管理端容器访问；`127.0.0.1` 指向管理端容器自身，不能用于访问容器外的 Go 服务。`ANBAN_ADMIN_USERNAME`、`ANBAN_ADMIN_PASSWORD`、数据库/MinIO 配置、`ANBAN_PUBLIC_URL` 均配置在 **Go 后端**，不放在管理端容器中。

独立部署使用 `ANBAN_ADMIN_ADDR=127.0.0.1:8025` 配置完整的宿主机监听地址。生产应通过 HTTPS 反向代理访问，否则浏览器不会发送 Secure 会话 Cookie。需要远程代理直接连接端口时，可设为 `ANBAN_ADMIN_ADDR=0.0.0.0:8025` 并在网络侧限制访问。

反向代理需要：

- 管理端域名转发至 `127.0.0.1:8025`；Go 后端域名转发至 `127.0.0.1:8024`。
- 保留正确的 `Host` / `X-Forwarded-Host` / `X-Forwarded-Proto`。不要开放任意 Server Action 跨域来源。
- 管理端 `/api/apk` 与 Go `/api/v1/admin/apks` 的请求体限制至少 **301 MB**，读写超时至少 **600 秒**（例如 Nginx `client_max_body_size 301m`、`proxy_read_timeout 600s`、`proxy_send_timeout 600s`）。建议关闭上传代理缓冲。公开下载接口也应允许长下载。
- 后端上传使用临时文件，Compose 已给只读后端提供 384 MB `/tmp`。较多并发上传时增加临时空间；当前界面一次上传一个包。

也可独立运行生产管理端：

```sh
npm run admin:build
HOSTNAME=127.0.0.1 PORT=8025 node --env-file-if-exists=.env admin/.next/standalone/server.js
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

测试在随机命名的独立 PostgreSQL schema 中运行，测试结束删除该 schema 及其中登记的测试 APK 对象，不改动业务资料。数据库账号需要创建 schema 的权限。覆盖独立管理端登录、同名 App 账号隔离、环境变量凭据变更与旧会话失效、App 会话不受影响、上传/下载、发布/暂停、并发编辑与重启保留业务配置。另有无需数据库的测试覆盖错误凭据、空密码禁用、会话过期、退出、并发访问及登录限流。
