# CLAUDE.md

Instructions for Claude Code when working with this repository.

**See [AGENT.md](AGENT.md) for full contributing guidelines.**

## Quick Reference

```bash
# Load the system
sbcl --load cl-mcp.asd --eval "(ql:quickload :cl-mcp)"

# Run tests
sbcl --load cl-mcp.asd \
     --eval "(ql:quickload :cl-mcp/tests)" \
     --eval "(asdf:test-system :cl-mcp)"
```

## Dependencies

@../opsis/claude.md
