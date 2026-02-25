;;; src/client/conditions.lisp
;;; ABOUTME: Client-specific MCP conditions

(in-package #:cl-mcp.client.conditions)

(define-condition mcp-connect-error (mcp-error)
  ((command :initarg :command :reader connect-error-command))
  (:report (lambda (c s)
             (format s "MCP connect error: ~a (command: ~{~a~^ ~})"
                     (error-message c)
                     (connect-error-command c))))
  (:documentation
   "Signaled when a connection to an MCP server cannot be established."))

(define-condition mcp-session-closed (mcp-error)
  ()
  (:report (lambda (c s)
             (format s "MCP session closed: ~a" (error-message c))))
  (:documentation
   "Signaled when an MCP session drops unexpectedly (subprocess exited,
    timeout, or EOF before expected)."))

(define-condition mcp-protocol-error (mcp-error)
  ()
  (:report (lambda (c s)
             (format s "MCP protocol error: ~a" (error-message c))))
  (:documentation
   "Signaled when the server returns a JSON-RPC error response for a valid
    session operation (e.g. method not found, invalid params).
    Unlike mcp-session-closed, the session is still alive after this error."))

(define-condition mcp-tool-error (mcp-error)
  ((tool-name :initarg :tool-name :reader tool-error-name)
   (content   :initarg :content   :reader tool-error-content))
  (:report (lambda (c s)
             (format s "MCP tool error (~a): ~a"
                     (tool-error-name c)
                     (error-message c))))
  (:documentation
   "Signaled when a tool call returns isError:true in its result.
    This is a tool-domain error, not a protocol error.
    Restarts established by callers: use-value, skip-tool."))
