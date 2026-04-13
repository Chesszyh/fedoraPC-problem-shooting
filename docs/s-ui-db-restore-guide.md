# s-ui 数据库端口查询说明

本文记录了如何从 `s-ui.db` 中查询 `tuic`、`hy2`（数据库内实际类型名为 `hysteria2`）以及 `vless-reality` 的监听端口，并据此判断云服务器入站安全组需要放行哪些端口和协议。

## 1. 查询目标

目标是直接从数据库中确认实际生效的入站监听端口，而不是依赖面板默认值、文档示例值或经验判断。

需要确认的协议：

- `tuic`
- `hy2`
- `vless-reality`

需要得到的结论：

- 监听端口是多少
- 该端口应放行 `TCP` 还是 `UDP`

## 2. 使用的数据库文件

脱敏示例中的数据库文件：

```text
/path/to/s-ui.db
```

## 3. 第一步：查看数据库有哪些表

先确认库中有哪些表，判断配置大概存放在哪里：

```bash
sqlite3 /path/to/s-ui.db '.tables'
```

查询结果：

```text
changes    endpoints  outbounds  stats      users
clients    inbounds   settings   tls
```

从表名可以初步判断，入站配置应重点看 `inbounds` 表。

## 4. 第二步：检查 `inbounds` 表结构

先看字段结构，避免误以为端口是扁平列：

```bash
sqlite3 /path/to/s-ui.db "PRAGMA table_info(inbounds);"
```

关键结果：

```text
0|id|INTEGER|0||1
1|type|TEXT|0||0
2|tag|TEXT|0||0
3|tls_id|INTEGER|0||0
4|addrs|BLOB|0||0
5|out_json|BLOB|0||0
6|options|BLOB|0||0
```

这里可以看出：

- 没有单独的 `port` 列
- 实际配置存放在 `options` 和 `out_json` 这类 JSON/BLOB 字段中

这也是为什么直接执行下面这种查询会报错：

```bash
sqlite3 /path/to/s-ui.db "SELECT id, type, listen, port, enable FROM inbounds;"
```

报错信息：

```text
Error: in prepare, no such column: listen
```

说明应该改为展开 `options` 或 `out_json` 内的文本内容来找 `listen_port` / `server_port`。

## 5. 第三步：查看当前有哪些入站协议

为了确认数据库里协议的准确命名，先列出所有 `type`：

```bash
sqlite3 /path/to/s-ui.db "SELECT DISTINCT lower(type) FROM inbounds ORDER BY 1;"
```

结果：

```text
hysteria2
tuic
vless
```

这里有一个重要点：

- 面板或日常说法里的 `hy2`
- 在数据库 `type` 中实际记录为 `hysteria2`

所以查询 `hy2` 时，不能只搜 `hy2`，要同时考虑 `hysteria2`。

## 6. 第四步：查询 `tuic` 的端口

查询语句：

```bash
sqlite3 /path/to/s-ui.db \
  "SELECT id, type, tag, quote(CAST(options AS TEXT)), quote(CAST(out_json AS TEXT))
   FROM inbounds
   WHERE lower(type) IN ('tuic','hy2');"
```

其中返回的 `tuic` 记录关键内容如下：

```text
2|tuic|tuic|'{
  "congestion_control": "bbr",
  "listen": "::",
  "listen_port": <shared-port>
}'|'{
  "congestion_control": "bbr",
  "server": "<server-ip>",
  "server_port": <shared-port>,
  ...
  "type": "tuic"
}'
```

可确认：

- `tuic` 的监听端口是 `<shared-port>`
- `options.listen_port` 和 `out_json.server_port` 一致，都是 `<shared-port>`

## 7. 第五步：查询 `hy2 / hysteria2` 的端口

查询语句：

```bash
sqlite3 /path/to/s-ui.db \
  "SELECT id, type, tag, quote(CAST(options AS TEXT))
   FROM inbounds
   WHERE lower(type) LIKE '%hy%' OR lower(tag) LIKE '%hy%';"
```

结果：

```text
3|hysteria2|hysteria2-27535|'{
  "down_mbps": 200,
  "listen": "::",
  "listen_port": <hy2-port>,
  "up_mbps": 200
}'
```

可确认：

- `hy2` 在数据库中对应 `hysteria2`
- 它的监听端口是 `<hy2-port>`

## 8. 第六步：查询 `vless-reality` 的端口和 Reality 标识

仅查询 `vless` 还不够，还需要确认它是否启用了 `reality`。

查询语句：

```bash
sqlite3 /path/to/s-ui.db \
  "SELECT id, type, tag, quote(CAST(options AS TEXT)), quote(CAST(out_json AS TEXT)), tls_id
   FROM inbounds
   WHERE lower(type)='vless';"
```

结果中的关键内容：

```text
1|vless|vless-reality|'{
  "listen": "::",
  "listen_port": <shared-port>,
  "multiplex": {},
  "transport": {}
}'|'{
  "server": "<server-ip>",
  "server_port": <shared-port>,
  "tag": "vless-reality",
  "tls": {
    "enabled": true,
    "reality": {
      "enabled": true,
      "public_key": "...",
      "short_id": "<short-id>"
    },
    "server_name": "<reality-server-name>",
    "utls": {
      "enabled": true,
      "fingerprint": "chrome"
    }
  },
  "transport": {},
  "type": "vless"
}'|1
```

可确认：

- 这条 `vless` 入站的标签是 `vless-reality`
- 监听端口是 `<shared-port>`
- `tls.reality.enabled` 为 `true`
- 因此它确实是 `vless-reality`

## 9. 如何判断该放行 TCP 还是 UDP

从协议特性判断：

- `VLESS-Reality` 通常工作在 `TCP`
- `TUIC` 基于 `QUIC`，需要放行 `UDP`
- `Hysteria2` 也基于 `QUIC`，需要放行 `UDP`

因此结合数据库端口查询结果，云服务器入站规则应放行：

```text
TCP <shared-port> -> VLESS-Reality
UDP <shared-port> -> TUIC
UDP <hy2-port>    -> Hysteria2 (hy2)
```

## 10. 最终结论

本数据库中的实际监听端口如下：

| 协议 | 数据库中的 type/tag | 监听端口 | 需要放行 |
|---|---|---:|---|
| VLESS-Reality | `type=vless`, `tag=vless-reality` | `<shared-port>` | `TCP <shared-port>` |
| TUIC | `type=tuic`, `tag=tuic` | `<shared-port>` | `UDP <shared-port>` |
| HY2 | `type=hysteria2` | `<hy2-port>` | `UDP <hy2-port>` |

## 11. 复查时可直接使用的命令清单

```bash
sqlite3 s-ui.db '.tables'
sqlite3 s-ui.db "PRAGMA table_info(inbounds);"
sqlite3 s-ui.db "SELECT DISTINCT lower(type) FROM inbounds ORDER BY 1;"
sqlite3 s-ui.db "SELECT id, type, tag, quote(CAST(options AS TEXT)), quote(CAST(out_json AS TEXT)) FROM inbounds WHERE lower(type) IN ('tuic','hy2');"
sqlite3 s-ui.db "SELECT id, type, tag, quote(CAST(options AS TEXT)) FROM inbounds WHERE lower(type) LIKE '%hy%' OR lower(tag) LIKE '%hy%';"
sqlite3 s-ui.db "SELECT id, type, tag, quote(CAST(options AS TEXT)), quote(CAST(out_json AS TEXT)), tls_id FROM inbounds WHERE lower(type)='vless';"
```

## 12. 注意事项

- 这里查询的是数据库中的实际配置，不是程序默认值。
- `hy2` 在库里显示为 `hysteria2`，查询时要注意名称差异。
- `vless-reality` 和 `tuic` 可以共用同一个端口，但一个走 `TCP`，一个走 `UDP`，两者不冲突。
- 如果后续面板里改过端口，应该重新执行上述查询，不要沿用本文中的端口数字。
