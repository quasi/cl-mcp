# cl-mcp

MCP **server** *and* **client** framework for Common Lisp.

**Server**: expose any CL function as an MCP tool — `make-server` → `register-tool` → `run-server`.

**Client**: connect to any MCP server subprocess, list tools, call tools — `make-client` → `connect` → `list-tools` / `call-tool`.

Framework handles JSON-RPC 2.0 framing, NDJSON stdio transport, MCP protocol negotiation, tool validation, threading, and error recovery. Consumer code is pure business logic.

**Protocol**: MCP 2025-06-18 (server) / 2025-11-25 (client) | **Language**: Common Lisp (SBCL) | **License**: MIT

*Ships dev and integration SKILLS for your agent.*

## Quick Start — Server

```bash
sbcl --load cl-mcp.asd --eval "(ql:quickload :cl-mcp)"
```

```lisp
(defvar *server* (cl-mcp:make-server :name "my-server" :version "1.0.0"))
(cl-mcp:register-tool *server* "ping"
  :description "Returns pong"
  :schema '(("type" . "object"))
  :handler (lambda (args) (declare (ignore args)) "pong"))
(cl-mcp:run-server *server*)
```

## Quick Start — Client

```bash
sbcl --load cl-mcp.asd --eval "(ql:quickload :cl-mcp/client)"
```

```lisp
(cl-mcp.client:with-mcp-client (client
    :name "my-agent"
    :command '("npx" "@modelcontextprotocol/server-filesystem" "/tmp"))
  (let ((tools (cl-mcp.client:list-tools client)))
    (format t "Available tools: ~{~a~^, ~}~%"
            (mapcar (lambda (t) (getf t :name)) tools)))
  (let ((result (cl-mcp.client:call-tool client "read_file"
                                         '(("path" . "/tmp/hello.txt")))))
    (print (getf result :content))))
```

## Documentation

| Document | Audience | Purpose |
|----------|----------|---------|
| [.claude/skills/integration/SKILL.md](.claude/skills/integration/SKILL.md) | Consumers | Using cl-mcp (server + client) in a project |
| [.claude/skills/dev/SKILL.md](.claude/skills/dev/SKILL.md) | Contributors | Working on cl-mcp |

## Running Tests

```bash
# Server tests
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/tests)" \
     --eval "(asdf:test-system :cl-mcp)"

# Client tests
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/client-tests)" \
     --eval "(asdf:test-system :cl-mcp/client)"
```

## Authors

Abhijit Rao / quasi / quasiLabs
