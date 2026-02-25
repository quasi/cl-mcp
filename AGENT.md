# AGENT.md

**Contributing Agent Instructions for cl-mcp**

## Project Context

**Name**: cl-mcp
**Language**: Common Lisp
**Implementation**: SBCL
**Build System**: ASDF
**Protocol**: Model Context Protocol (MCP) 2025-06-18

## What This Project Does

A reusable MCP server framework for Common Lisp. Consumers create a server, register tools, and call `run-server`. The framework handles JSON-RPC 2.0 framing, stdio transport, MCP protocol dispatch, tool validation, and error recovery.

Consumers: cl-mcp-server (CL REPL tools), chatterbox, ghost.

## Build Commands

```bash
# Load
sbcl --load cl-mcp.asd --eval "(ql:quickload :cl-mcp)"

# Test
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/tests)" \
     --eval "(asdf:test-system :cl-mcp)"
```

## Code Conventions

### Package Structure

| Package | Contains |
|---------|----------|
| `cl-mcp.conditions` | JSON-RPC error conditions |
| `cl-mcp.json-rpc` | Message structs, parsing, encoding |
| `cl-mcp.transport` | Stdio read/write |
| `cl-mcp.tools` | Tool registry (per-server, no global state) |
| `cl-mcp` | `mcp-server`, `make-server`, `register-tool`, `run-server` |

### Naming

| Type | Convention | Example |
|------|------------|---------|
| Special variables | `*earmuffs*` | none currently |
| Constants | `+plus-signs+` | none currently |
| Predicates | `-p` suffix | `notification-p`, `content-block-list-p` |
| Constructors | `make-` prefix | `make-server`, `make-request` |
| Internal functions | `%` prefix | `%handle-initialize` |

### File Organization

Each file begins with an ABOUTME comment:

```lisp
;;; ABOUTME: Brief description of what this file provides
```

## Architecture Rules

### RULE-001: Request-Response Guarantee

Every valid JSON-RPC request MUST receive exactly one response.

### RULE-002: Server Stability

The server MUST NOT terminate due to handler errors. Errors are caught and returned as JSON-RPC error responses.

### RULE-003: Per-Server Tool Registry

Each `mcp-server` instance has its own tool registry. There is no global `*tools*` variable. This prevents cross-instance contamination.

### RULE-004: Handler Contract

Tool handlers take `(arguments)` and return either:
- A string (wrapped into a text content block)
- A list of MCP content blocks (passed through)

Consumer state belongs in closures, not in the handler signature.

## Key Invariants

1. **INV-001**: Every valid JSON-RPC request receives exactly one response
2. **INV-002**: Server never terminates due to handler errors
3. **INV-003**: Tool registries are per-server instance (no global state)
4. **INV-004**: Handler results are normalized to MCP content format
5. **INV-005**: All messages conform to JSON-RPC 2.0

## Testing

Uses FiveAM. Test suites: conditions, json-rpc, encoding, transport, tools, server.

```bash
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/tests)" \
     --eval "(asdf:test-system :cl-mcp)"
```
