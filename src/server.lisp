;;; src/server.lisp
;;; ABOUTME: MCP server — configurable object with protocol dispatch

(in-package #:cl-mcp)

;;; Server Structure

(defstruct (mcp-server (:conc-name mcp-server-))
  "An MCP server instance with its own tool registry."
  (name "mcp-server" :type string)
  (version "0.1.0" :type string)
  (protocol-version "2025-06-18" :type string)
  (tools (make-hash-table :test #'equal)))

(defun make-server (&key (name "mcp-server") (version "0.1.0"))
  "Create an MCP server instance with its own tool registry."
  (make-mcp-server :name name :version version))

;;; Public API

(defun register-tool (server name &key description schema handler)
  "Register a tool on SERVER's registry.
HANDLER is (lambda (arguments) ...) returning a string or content-block list."
  (cl-mcp.tools:register-tool
   (mcp-server-tools server) name
   (or description "") (or schema '(("type" . "object"))) handler))

;;; Internal MCP Handlers

(defun %handle-initialize (server id)
  "Handle the initialize request."
  (let ((empty-obj (make-hash-table :test #'equal)))
    (make-success-response
     :id id
     :result `(("protocolVersion" . ,(mcp-server-protocol-version server))
               ("serverInfo" . (("name" . ,(mcp-server-name server))
                                ("version" . ,(mcp-server-version server))))
               ("capabilities" . (("tools" . ,empty-obj)))))))

(defun %handle-tools-list (server id)
  "Handle the tools/list request."
  (make-success-response
   :id id
   :result `(("tools" . ,(cl-mcp.tools:tools-for-mcp
                           (mcp-server-tools server))))))

(defun %handle-tools-call (server id params)
  "Handle the tools/call request."
  (let ((name (cdr (assoc "name" params :test #'string=)))
        (arguments (cdr (assoc "arguments" params :test #'string=))))
    (handler-case
        (let ((content (cl-mcp.tools:call-tool
                        (mcp-server-tools server) name arguments)))
          (make-success-response
           :id id
           :result `(("content" . ,content))))
      (method-not-found (c)
        (make-error-response
         :id id
         :code (error-code c)
         :message (error-message c)))
      (invalid-params (c)
        (make-error-response
         :id id
         :code (error-code c)
         :message (error-message c))))))

;;; Request Dispatcher

(defun %handle-request (server request)
  "Dispatch a JSON-RPC request. Returns nil for notifications."
  (when (notification-p request)
    (return-from %handle-request nil))
  (let ((id (request-id request))
        (method (request-method request))
        (params (request-params request))
        (source (mcp-server-name server)))
    (handler-case
        (cond
          ((string= method "initialize")
           (%handle-initialize server id))
          ((string= method "tools/list")
           (%handle-tools-list server id))
          ((string= method "tools/call")
           (%handle-tools-call server id params))
          (t
           (error 'method-not-found
                  :message (format nil "Method not found: ~a" method))))
      (method-not-found (c)
        (make-error-response
         :id id
         :code (error-code c)
         :message (error-message c)))
      (invalid-params (c)
        (make-error-response
         :id id
         :code (error-code c)
         :message (error-message c)))
      (error (c)
        (opsis/c:emit :request-failed :source source :level :error
                      :message (princ-to-string c)
                      :data (list :method method))
        (make-error-response
         :id id
         :code -32603
         :message (format nil "Internal error: ~a" c))))))

;;; Server Main Loop

(defun run-server (server &key (input *standard-input*) (output *standard-output*))
  "Run the MCP server loop. Blocks until EOF on INPUT.
Handles MCP handshake, tool dispatch, and error recovery.
Emits opsis events at protocol lifecycle points."
  (let ((source (mcp-server-name server)))
    (opsis/c:emit :server-started :source source :level :info
                  :message "MCP server ready")
    (loop
      (handler-case
          (let ((request (read-message input)))
            (unless request
              (opsis/c:emit :server-stopped :source source :level :info
                            :message "EOF received")
              (return))
            (opsis/c:emit :request-received :source source
                          :data (list :method (request-method request)))
            (let ((response (%handle-request server request)))
              (when response
                (write-message response output))))
        (json-rpc-error (c)
          (opsis/c:emit :request-failed :source source :level :error
                        :message (princ-to-string c))
          (write-message
           (make-error-response
            :id nil
            :code (error-code c)
            :message (error-message c))
           output))
        (error (c)
          (opsis/c:emit :request-failed :source source :level :error
                        :message (princ-to-string c))
          (write-message
           (make-error-response
            :id nil
            :code -32603
            :message (format nil "Internal error: ~a" c))
           output))))))
