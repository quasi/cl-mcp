---
name: cl-mcp-integration
description: Integration guide for using cl-mcp in a project
version: 0.1.0
author: quasi
type: integration
---

# cl-mcp — Integration Skill

## What Is cl-mcp

MCP server framework for Common Lisp. Three calls to a running MCP server: `make-server` → `register-tool` (×N) → `run-server`. The framework handles JSON-RPC 2.0 framing, NDJSON stdio transport, MCP protocol negotiation, tool argument validation, and error recovery. Consumers only write tool handlers.

Protocol: MCP 2025-06-18.

## Quick Start

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
;; Load
(ql:quickload :cl-mcp)

;; Create server
(defvar *server* (cl-mcp:make-server :name "my-server" :version "1.0.0"))

;; Register a tool
(cl-mcp:register-tool *server* "greet"
  :description "Returns a greeting"
  :schema '(("type" . "object")
            ("required" . ("name"))
            ("properties" . (("name" . (("type" . "string"))))))
  :handler (lambda (args)
             (format nil "Hello, ~a!"
                     (cdr (assoc "name" args :test #'string=)))))

;; Run (blocks until EOF on stdin)
(cl-mcp:run-server *server*)
```

## Core Concepts

**Server**: `mcp-server` struct with an isolated tool registry. Multiple servers can run independently in the same image.

**Tool registry**: Per-server hash-table. `register-tool` mutates it. No global state.

**Handler**: `(lambda (args) ...)`. `args` is an alist — string keys mapped to decoded JSON values (strings, numbers, lists, nested alists).

**Result normalization**: Return a string → auto-wrapped to `(("type" . "text") ("text" . ...))`. Return a list of content blocks → used as-is.

**Error recovery**: Server catches all handler errors and returns JSON-RPC `internal-error` (-32603). Server never terminates on error.

**Observability**: Server emits `opsis/conditions` events at lifecycle points. Attach opsis handlers before calling `run-server`.

## Key API

All symbols in package `cl-mcp`.

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `make-server` | `(&key name version)` | `mcp-server` | Defaults: `"mcp-server"`, `"0.1.0"` |
| `register-tool` | `(server name &key description schema handler)` | `cl-mcp.tools:tool-definition` | `handler` is required (function); return type is not exported from `cl-mcp` |
| `run-server` | `(server &key input output)` | — | Blocks until EOF. Defaults: `*standard-input*`, `*standard-output*` |
| `mcp-server-name` | `(server)` | `string` | Accessor |
| `mcp-server-version` | `(server)` | `string` | Accessor |
| `mcp-server-tools` | `(server)` | `hash-table` | Registry; use for testing |

### Schema Format

`schema` is an alist representing a JSON Schema object:

```lisp
'(("type" . "object")
  ("required" . ("arg1" "arg2"))          ; list of required arg names
  ("properties" . (("arg1" . (("type" . "string")))
                   ("arg2" . (("type" . "number"))))))
```

Omitting `schema` defaults to `(("type" . "object"))` (accepts anything, validates nothing).

## Common Patterns

### PATTERN-001: Minimal Server

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(let ((server (cl-mcp:make-server :name "ping-server" :version "1.0.0")))
  (cl-mcp:register-tool server "ping"
    :description "Returns pong"
    :schema '(("type" . "object"))
    :handler (lambda (args) (declare (ignore args)) "pong"))
  (cl-mcp:run-server server))
```

**Rules satisfied**: RULE-003 (per-server registry), RULE-004 (handler contract).

### PATTERN-002: Tool With Required Arguments

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
               ;; return string; framework wraps to text content block
               (format nil "~a" (+ a b)))))
```

Missing `"a"` or `"b"` signals `invalid-params` (-32602) — handled automatically.

### PATTERN-003: Stateful Tool Via Closure

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
;; State lives in closure, not global variable (RULE-003)
(let ((counter 0))
  (cl-mcp:register-tool server "count"
    :description "Increments and returns counter"
    :schema '(("type" . "object"))
    :handler (lambda (args)
               (declare (ignore args))
               (format nil "~a" (incf counter)))))
```

### PATTERN-004: Multiple Content Blocks

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
(cl-mcp:register-tool server "report"
  :description "Returns structured report"
  :schema '(("type" . "object"))
  :handler (lambda (args)
             (declare (ignore args))
             ;; list of content blocks passed through as-is
             '((("type" . "text") ("text" . "Summary: OK"))
               (("type" . "text") ("text" . "Details: none")))))
```

### PATTERN-005: Custom I/O (Testing / Piped Transport)

<!-- Not machine-verified: requires SBCL with cl-mcp loaded -->
```lisp
;; Useful for integration tests or custom transport
(with-open-file (in "/tmp/input.ndjson" :direction :input)
  (with-open-file (out "/tmp/output.ndjson"
                       :direction :output
                       :if-exists :supersede)
    (cl-mcp:run-server server :input in :output out)))
```

## Pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| `invalid-params` on valid call | Schema `"required"` list has the arg name | Check alist key spelling (case-sensitive) |
| `method-not-found` on known tool | `register-tool` called after `run-server` | Register all tools before starting loop |
| Handler error → client gets `-32603` | Server catches all errors silently | Return error info as string; inspect opsis events |
| `run-server` never returns | Blocks until EOF on `input` | Call from dedicated thread or at top level |
| State shared across clients | Global variable used instead of closure | Move state into `let` wrapping `register-tool` |
| Wrong arg type from JSON | Numbers come as CL numbers, strings as CL strings | Use `numberp`/`stringp` before coercing |

## MCP Methods Supported

| Method | Triggers |
|--------|---------|
| `initialize` | Returns `protocolVersion`, `serverInfo`, `capabilities` |
| `tools/list` | Returns all registered tool definitions |
| `tools/call` | Validates args, calls handler, returns content blocks |
| Notifications | Silently ignored (no response sent) |
| Any other method | Returns `method-not-found` (-32601) |

## Error Conditions (Re-exported from `cl-mcp`)

| Condition | Code | Trigger |
|-----------|------|---------|
| `parse-error` | -32700 | Malformed JSON |
| `invalid-request` | -32600 | Missing `jsonrpc`/`method` field, or `jsonrpc` ≠ `"2.0"`, or `method` is not a string |
| `method-not-found` | -32601 | Unknown method or tool name |
| `invalid-params` | -32602 | Missing required tool argument |
| `internal-error` | -32603 | Handler signaled a condition |

Accessors: `error-code`, `error-message`, `error-data`.

## References

- [Dev Skill](../dev/SKILL.md) — for contributors working on cl-mcp
- [README.md](../../../README.md) — project navigation
