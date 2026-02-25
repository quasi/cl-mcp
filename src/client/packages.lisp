;;; src/client/packages.lisp
;;; ABOUTME: Package definitions for cl-mcp/client

(defpackage #:cl-mcp.client.conditions
  (:use #:cl #:cl-mcp.conditions)
  (:shadowing-import-from #:cl-mcp.conditions #:parse-error)
  (:export
   ;; Condition types
   #:mcp-connect-error
   #:mcp-session-closed
   #:mcp-protocol-error
   #:mcp-tool-error
   ;; Accessors
   #:connect-error-command
   #:tool-error-name
   #:tool-error-content))

(defpackage #:cl-mcp.client
  (:use #:cl
        #:cl-mcp.conditions
        #:cl-mcp.json-rpc
        #:cl-mcp.transport
        #:cl-mcp.client.conditions)
  (:shadowing-import-from #:cl-mcp.conditions #:parse-error)
  (:export
   ;; Protocol utilities (exported for testing)
   #:encode-request
   #:parse-client-message
   #:make-id-generator
   #:pending-request
   #:make-pending-request
   #:pending-request-done
   #:pending-request-result
   #:fulfill-promise
   #:await-promise
   ;; Client struct
   #:mcp-client
   #:make-client
   #:client-name
   #:client-version
   #:client-command
   #:client-connected-p
   #:client-server-info
   #:client-server-capabilities
   ;; Public API
   #:connect
   #:disconnect
   #:list-tools
   #:call-tool
   #:with-mcp-client))
