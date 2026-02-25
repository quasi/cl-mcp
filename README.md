# cl-mcp

Model Context Protocol server framework for Common Lisp.

Consumers create a server, register tools, and call `run-server`. The framework handles JSON-RPC 2.0 framing, stdio transport, MCP protocol dispatch, tool validation, and error recovery.

**Protocol**: MCP 2025-06-18 | **Language**: Common Lisp (SBCL) | **License**: MIT

*Ships with dev OR integration SKILLS for your agent.*

## Quick Start

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

## Documentation

| Document | Audience | Purpose |
|----------|----------|---------|
| [.claude/skills/integration/SKILL.md](.claude/skills/integration/SKILL.md) | Consumers | Using cl-mcp in a project |
| [.claude/skills/dev/SKILL.md](.claude/skills/dev/SKILL.md) | Contributors | Working on cl-mcp |
| [AGENT.md](AGENT.md) | Agents (legacy) | Contributing guidelines |

## Running Tests

```bash
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/tests)" \
     --eval "(asdf:test-system :cl-mcp)"
```

## Authors

Abhjit Rao / quasi / quasiLabs
