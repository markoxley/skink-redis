# skink-redis

Redis client for Skink: a pure-Skink RESP2/RESP3 wire-protocol
implementation — no native dependencies — built on
[`skink-dbx`](../skink-dbx). Covers the command surface (strings, keys,
counters, lists, hashes, sets, sorted sets), one-round-trip pipelines,
pub/sub, TLS (`rediss://`), RESP3 negotiation (`HELLO 3`), and an
adapter registering Redis as a `dbx.Driver`.

## Installation

```sh
scales add mod/markoxley/skink-redis
scales install          # also fetches the skink-dbx dependency
```

```skink
import "mod/markoxley/skink-redis"
```

## Connecting

```skink
c, err := redis.Dial("redis://127.0.0.1:6379/0")
// redis://[user:pass@]host[:port][/db][?protocol=3][&timeout_ms=N]
// rediss://... for TLS (default port 6379 either way) —
// rediss:// enforces full CA chain + hostname verification;
// there is no insecure-skip-verify escape hatch
```

or explicitly:

```skink
c, err := redis.Connect("127.0.0.1", 6379, 0, "default", "secret", 3000)
```

`Dial` performs the full handshake: TLS upgrade for `rediss://`,
optional `HELLO 3` (falls back to RESP2 on pre-6.0 servers), `AUTH`
when credentials are present, and `SELECT` when a db index is given.

## Commands

Every command is a `Do(args)` call; typed helpers cover the common
surface:

```skink
c.Set("key", "value")
v, ok, err := c.GetString("key")
c.SetEx("session", "tok", 300)        // SET with TTL seconds
ok, err = c.SetNX("lock", "owner")
n, err := c.Incr("counter")
lr, err := c.LRange("list", int64(0), int64(-1))
hv, err := c.HGet("hash", "field")
sm, err := c.SMembers("set")
zr, err := c.ZRange("zset", int64(0), int64(-1))
c.Expire("key", 60)
ttl, err := c.Ttl("key")
```

Raw replies are `redis_resp.Resp` values with `AsString`/`AsInt`/
`AsFloat`/`IsNull`/`IsError`/`Strings` accessors. `-ERR` replies surface
as `errors.Error`.

## Pipelining

```skink
p := redis.NewPipeline(&c)
p.Add([]string{"SET", "a", "1"})
p.Add([]string{"INCR", "n"})
rs, err := p.Exec()   // one write + one read pass, replies in order
```

Per-command errors stay in their `Resp` slots (`KindError`); a
transport failure fails `Exec` as a whole.

## Pub/Sub

`SUBSCRIBE` puts a connection into subscribe mode — use a dedicated one:

```skink
ps, err := redis.DialPubSub("redis://127.0.0.1:6379")
ps.Subscribe([]string{"events"})
for {
    m, rerr := ps.Receive(1000) // 0 = block forever
    if m.Kind == redis.MsgMessage {
        // m.Channel, m.Payload
    }
}
```

Pattern subscriptions via `PSubscribe` deliver `MsgPMessage` (with
`Pattern` set). `Unsubscribe`/`PUnsubscribe`/`PingSub`/`Close` round
out the API.

## Generic dbx access

```skink
redis.Register() // installs the "redis"/"rediss" scheme driver
conn, err := dbx.Open("redis://127.0.0.1:6379")
rows, _ := conn.Query("get", []dbx_value.Value{dbx_value.Text("k")})
```

`Query`/`Exec` map `(sql, args)` to `(COMMAND, args...)`; replies map to
a `Rows` (`value` column, or `key`/`value` for map replies).
`Begin`/`Commit`/`Rollback` map to `MULTI`/`EXEC`/`DISCARD`.

## Layout

| file | contents |
|------|----------|
| `redis_resp`   | RESP2/RESP3 `Resp` model + wire codec |
| `redis_client` | `Client`, DSN connect, AUTH/SELECT/HELLO, typed commands |
| `redis_pipe`   | `Pipeline` — batched one-round-trip commands |
| `redis_pubsub` | `PubSub` — subscribe-mode conn + `Message` delivery |
| `redis_dbx`    | `dbx.Driver` adapter (scheme `redis`) |
| `testkit`      | scripted in-process RESP server used by the tests |

## Testing

```sh
./run_tests.sh    # unit suites (in-process scripted server, no deps)
./test_live.sh    # live test vs a podman redis:7 container
```

`test_live.sh` starts a throwaway container on 127.0.0.1:16399, runs
`live_test.skink`, and tears down. Point it elsewhere with
`SKINK_REDIS_DSN=redis://host:port/db ./test_live.sh`.

## Notes & limits

- Skink strings are NUL-terminated: command **arguments** cannot
  contain embedded NUL bytes. Reply payloads carry their exact wire
  length in `Resp.Len` and can hold binary data.
- `Client` is not safe for concurrent use — take connections from a
  pool (`dbx_pool`) or use one per thread.
- RESP3 attributes (`|`) are decoded and discarded.

## License

Apache-2.0
