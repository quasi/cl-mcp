---
name: cl-mcp-integration
description: Integration guide for using cl-mcp (server + client) in a project
version: 0.2.0
author: quasi
type: integration
---

# cl-mcp — Integration Skill

## What Is cl-mcp

MCP **server and client** framework for Common Lisp.

- **`cl-mcp`** (server): Expose CL functions as MCP tools over stdio. Framework handles JSON-RPC framing, protocol negotiation, tool validation, error recovery.
- **`cl-mcp/client`** (client): Connect to any MCP server subprocess, list its tools, call them. Threading, request correlation, and error signaling handled by the framework.

Protocol: MCP 2025-06-18 (server) / 2025-11-25 (client).

---

## SERVER

### Quick Start

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(ql:quickload :cl-mcp)

(defvar *server* (cl-mcp:make-server :name "my-server" :version "1.0.0"))

(cl-mcp:register-tool *server* "greet"
  :description "Returns a greeting"
  :schema '(("type" . "object")
            ("required" . ("name"))
            ("properties" . (("name" . (("type" . "string"))))))
  :handler (lambda (args)
             (format nil "Hello, ~a!"
                     (cdr (assoc "name" args :test #'string=)))))

(cl-mcp:run-server *server*)  ; blocks until EOF on stdin
```

### Core Concepts (Server)

**Server**: `mcp-server` struct with an isolated tool registry. Multiple servers can run independently in the same image.

**Tool registry**: Per-server hash-table. `register-tool` mutates it. No global state.

**Handler**: `(lambda (args) ...)`. `args` is an alist — string keys mapped to decoded JSON values (strings, numbers, lists, nested alists).

**Result normalization**: Return a string → auto-wrapped to `(("type" . "text") ("text" . ...))`. Return a list of content blocks → used as-is.

**Error recovery**: Server catches all handler errors and returns JSON-RPC `internal-error` (-32603). Server never terminates on error.

### Server API

All symbols in package `cl-mcp`.

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `make-server` | `(&key name version)` | `mcp-server` | Defaults: `"mcp-server"`, `"0.1.0"` |
| `register-tool` | `(server name &key description schema handler)` | `tool-definition` | `handler` required; call before `run-server` |
| `run-server` | `(server &key input output)` | — | Blocks until EOF. Defaults: `*standard-input*`, `*standard-output*` |
| `mcp-server-name` | `(server)` | `string` | Accessor |
| `mcp-server-version` | `(server)` | `string` | Accessor |
| `mcp-server-tools` | `(server)` | `hash-table` | Registry; use for testing |

#### Schema Format

```lisp
'(("type" . "object")
  ("required" . ("arg1" "arg2"))
  ("properties" . (("arg1" . (("type" . "string")))
                   ("arg2" . (("type" . "number"))))))
```

Omitting `schema` defaults to `(("type" . "object"))` — accepts anything, validates nothing.

### Server Patterns

#### PATTERN-001: Minimal Server

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(let ((server (cl-mcp:make-server :name "ping-server" :version "1.0.0")))
  (cl-mcp:register-tool server "ping"
    :description "Returns pong"
    :schema '(("type" . "object"))
    :handler (lambda (args) (declare (ignore args)) "pong"))
  (cl-mcp:run-server server))
```

#### PATTERN-002: Tool With Required Arguments

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(cl-mcp:register-tool server "add"
  :description "Adds two numbers"
  :schema '(("type" . "object")
            ("required" . ("a" "b"))
            ("properties" . (("a" . (("type" . "number")))
                             ("b" . (("type" . "number"))))))
  :handler (lambda (args)
             (let ((a (cdr (assoc "a" args :test #'string=)))
                   (b (cdr (assoc "b" args :test #'string=))))
               (format nil "~a" (+ a b)))))
```

Missing `"a"` or `"b"` signals `invalid-params` (-32602) automatically.

#### PATTERN-003: Stateful Tool Via Closure

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
;; State lives in closure, not global variable
(let ((counter 0))
  (cl-mcp:register-tool server "count"
    :description "Increments and returns counter"
    :schema '(("type" . "object"))
    :handler (lambda (args)
               (declare (ignore args))
               (format nil "~a" (incf counter)))))
```

#### PATTERN-004: Multiple Content Blocks

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(cl-mcp:register-tool server "report"
  :description "Returns structured report"
  :schema '(("type" . "object"))
  :handler (lambda (args)
             (declare (ignore args))
             '((("type" . "text") ("text" . "Summary: OK"))
               (("type" . "text") ("text" . "Details: none")))))
```

#### PATTERN-005: Custom I/O (Testing / Piped Transport)

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(with-open-file (in "/tmp/input.ndjson" :direction :input)
  (with-open-file (out "/tmp/output.ndjson"
                       :direction :output
                       :if-exists :supersede)
    (cl-mcp:run-server server :input in :output out)))
```

### Server Pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| `invalid-params` on valid call | Schema `"required"` has the arg name | Check alist key spelling (case-sensitive) |
| `method-not-found` on known tool | `register-tool` called after `run-server` | Register all tools before starting loop |
| Handler error → client gets `-32603` | Server catches all errors silently | Return error info as string; inspect opsis events |
| `run-server` never returns | Blocks until EOF on `input` | Call from dedicated thread or at top level |
| State shared across clients | Global variable instead of closure | Move state into `let` wrapping `register-tool` |
| Wrong arg type from JSON | Numbers as CL numbers, strings as CL strings | Use `numberp`/`stringp` before coercing |

---

## CLIENT

### Quick Start

<!-- Not machine-verified: requires SBCL with cl-mcp/client loaded -->
```lisp
(ql:quickload :cl-mcp/client)

(cl-mcp.client:with-mcp-client (client
    :name "my-agent"
    :command '("npx" "@modelcontextprotocol/server-filesystem" "/tmp"))
  ;; List available tools
  (let ((tools (cl-mcp.client:list-tools client)))
    (dolist (tool tools)
      (format t "~a: ~a~%" (getf tool :name) (getf tool :description))))
  ;; Call a tool
  (let ((result (cl-mcp.client:call-tool
                 client "read_file" '(("path" . "/tmp/hello.txt")))))
    (print (getf result :content))))
```

### Core Concepts (Client)

**mcp-client**: struct holding process handle, I/O streams, reader thread, pending-request table, and session state.

**connect**: Spawns the server subprocess, starts the reader thread, performs the MCP initialization handshake. Mutates the client struct.

**Reader thread**: Reads server stdout in a loop. Parses each line as JSON-RPC. Fulfills the matching pending-request promise. Exits cleanly on EOF.

**Pending-request promise**: One-shot synchronization object. `%send-request` registers it before writing to stdin, then blocks. Reader thread fulfills it; caller unblocks and returns the response.

**Pagination**: `list-tools` handles `nextCursor` pagination automatically — returns all tools across pages.

**Error taxonomy**:

| Condition | When signaled |
|-----------|--------------|
| `mcp-connect-error` | Subprocess fails to start or handshake fails |
| `mcp-session-closed` | EOF or timeout waiting for response |
| `mcp-protocol-error` | Server returns JSON-RPC error for a valid session op (session still alive) |
| `mcp-tool-error` | Tool call returns `isError: true` |

`mcp-tool-error` establishes two restarts: `use-value` (return a specific value) and `skip-tool` (return nil content). `use-value` shadows the CL standard restart of the same name within the dynamic extent of `call-tool` — do not rely on the standard `use-value` restart inside `call-tool` call stacks.

### Client API

All symbols in package `cl-mcp.client`.

| Function / Macro | Signature | Returns | Notes |
|-----------------|-----------|---------|-------|
| `make-client` | `(&key name version command)` | `mcp-client` | `command` is a list of strings |
| `connect` | `(client)` | `client` | Spawns subprocess + handshake. Signals `mcp-connect-error` on failure |
| `disconnect` | `(client &key timeout)` | `t` | Closes stdin, joins reader thread (kills if timeout), terminates process |
| `list-tools` | `(client)` | list of plists | Each plist: `(:name NAME :description DESC :input-schema SCHEMA)` |
| `call-tool` | `(client name arguments)` | plist | `arguments` is alist or hash-table. Returns `(:content CONTENT :is-error BOOL)` |
| `with-mcp-client` | `((var &rest make-args) &body body)` | — | Connects on entry, disconnects on exit (unwind-protect) |

Client struct accessors (read-only after connect):
- `client-name`, `client-version`, `client-command`
- `client-connected-p` — boolean
- `client-server-info` — alist: server name and version from handshake
- `client-server-capabilities` — alist from initialize response

### Client Patterns

#### PATTERN-006: Safe Session With with-mcp-client

<!-- Not machine-verified: requires SBCL with cl-mcp/client loaded and an MCP server available -->
```lisp
;; Preferred — disconnect guaranteed even on error
(cl-mcp.client:with-mcp-client (client
    :name "orchestrator"
    :command '("python" "-m" "my_mcp_server"))
  (let ((tools (cl-mcp.client:list-tools client)))
    (format t "~a tools available~%" (length tools))))
```

#### PATTERN-007: Manual Connect/Disconnect

<!-- Not machine-verified: requires SBCL with cl-mcp/client loaded -->
```lisp
(let ((client (cl-mcp.client:make-client
               :name "orchestrator"
               :command '("node" "server.js"))))
  (handler-case
      (progn
        (cl-mcp.client:connect client)
        (cl-mcp.client:call-tool client "ping" nil))
    (cl-mcp.client.conditions:mcp-connect-error (c)
      (format t "Could not connect: ~a~%" c)))
  (cl-mcp.client:disconnect client))
```

#### PATTERN-008: Handling Tool Errors With Restarts

<!-- Not machine-verified: requires SBCL with cl-mcp/client loaded -->
```lisp
(handler-bind
    ((cl-mcp.client.conditions:mcp-tool-error
      (lambda (c)
        ;; Log and continue with nil
        (format t "Tool ~a failed: ~a~%"
                (cl-mcp.client.conditions:tool-error-name c)
                (cl-mcp.client.conditions:tool-error-content c))
        (invoke-restart 'skip-tool))))
  (cl-mcp.client:call-tool client "risky-tool" '(("x" . 1))))
```

#### PATTERN-009: Inspecting Server Capabilities

<!-- Not machine-verified: requires SBCL with cl-mcp/client loaded -->
```lisp
(cl-mcp.client:with-mcp-client (client :command '("my-server"))
  ;; Inspect handshake results
  (let ((info (cl-mcp.client:client-server-info client)))
    (format t "Connected to: ~a ~a~%"
            (cdr (assoc "name"    info :test #'string=))
            (cdr (assoc "version" info :test #'string=)))))
```

### Client Pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| `mcp-connect-error` on known-good server | Server not on PATH | Use absolute path in `command` |
| `mcp-session-closed` (timeout) | Server slow to start | Increase `%send-request` `:timeout` (default 30s) |
| `mcp-tool-error` not handled → unwind | Tool returns `isError: true` | Use `handler-bind` with `skip-tool` or `use-value` restart |
| `disconnect` hangs | Reader thread stuck | Pass `:timeout` to `disconnect` (default 5s); thread is force-killed after |
| `call-tool` with nil arguments | Empty hash-table sent | Pass `nil` — framework converts to empty object |
| `list-tools` returns partial list | Assumed single page | `list-tools` paginates automatically; always correct |

---

## MCP Methods Supported

### Server

| Method | Response |
|--------|---------|
| `initialize` | `protocolVersion`, `serverInfo`, `capabilities` |
| `tools/list` | All registered tool definitions |
| `tools/call` | Validates args, calls handler, returns content blocks |
| Notifications | Silently ignored (no response sent) |
| Any other method | `method-not-found` (-32601) |

### Client

| Method sent | Purpose |
|------------|---------|
| `initialize` | Handshake — establishes session |
| `notifications/initialized` | Handshake completion notification |
| `tools/list` | Discover available tools (with pagination) |
| `tools/call` | Execute a tool |

## Error Conditions

### Server Conditions (package `cl-mcp`)

| Condition | Code | Trigger |
|-----------|------|---------|
| `parse-error` | -32700 | Malformed JSON |
| `invalid-request` | -32600 | Missing `jsonrpc`/`method` field |
| `method-not-found` | -32601 | Unknown method or tool name |
| `invalid-params` | -32602 | Missing required tool argument |
| `internal-error` | -32603 | Handler signaled a condition |

Accessors: `error-code`, `error-message`, `error-data`.

### Client Conditions (package `cl-mcp.client.conditions`)

| Condition | Accessor(s) | When |
|-----------|-------------|------|
| `mcp-connect-error` | `connect-error-command` | Subprocess launch or handshake failure |
| `mcp-session-closed` | — | EOF, timeout, or reader thread crash |
| `mcp-protocol-error` | — | JSON-RPC error on valid session op |
| `mcp-tool-error` | `tool-error-name`, `tool-error-content` | `isError: true` in tool result |

All inherit from `mcp-error` (from `cl-mcp.conditions`). Accessor `error-message` available on all.

---

## GHOST.MCP — Higher-Level Bridge

If you are using cl-mcp inside a **Ghost agent**, prefer the `ghost/mcp` bridge over calling `cl-mcp.client` directly. It converts MCP tools into native Ghost `tool-definition` objects automatically.

```lisp
(ql:quickload :ghost/mcp)

;; Convenience macro — wraps session, builds environment, disconnects on exit
(ghost.mcp:with-mcp-environment (env
    :command '("npx" "@modelcontextprotocol/server-filesystem" "/tmp"))
  (ghost:make-agent :provider provider :model model :environment env))
```

Lower-level: if you already hold a connected client, call `mcp-tools-from` directly:

```lisp
(cl-mcp.client:with-mcp-client (client :command '("my-server"))
  (let ((tools (ghost.mcp:mcp-tools-from client :safety-level :safe)))
    ;; tools is a list of cl-llm-provider:tool-definition
    (ghost.environment:make-environment :tools tools)))
```

Error mapping:

| cl-mcp condition | ghost.mcp behavior |
|-----------------|-------------------|
| `mcp-tool-error` (`isError: true`) | Handler returns LLM-visible string; session stays alive |
| `mcp-session-closed` | Propagated — Ghost agent loop signals `agent-tool-error` |
| `mcp-protocol-error` | Propagated — Ghost agent loop signals `agent-tool-error` |

Package: `ghost.mcp`. ASDF system: `ghost/mcp` (separate from `:ghost`).

---

## References

- [Dev Skill](../dev/SKILL.md) — for contributors working on cl-mcp
- [README.md](../../../README.md) — project navigation
