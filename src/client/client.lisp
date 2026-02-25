;;; src/client/client.lisp
;;; ABOUTME: MCP client — connect to servers, list tools, call tools
;;;
;;; Threading model:
;;;   Caller thread  — calls connect/list-tools/call-tool/disconnect
;;;   Reader thread  — reads lines from server stdout, fulfills pending promises
;;;
;;; Synchronization:
;;;   pending-lock   — protects the pending hash-table and next-id counter
;;;   Each pending-request has its own lock+condvar for caller/reader rendezvous

(in-package #:cl-mcp.client)

;;; ──────────────────────────────────────────────────────────────────────────
;;; mcp-client struct
;;; ──────────────────────────────────────────────────────────────────────────

(defstruct (mcp-client (:conc-name client-))
  "An MCP client session. Created with make-client, activated with connect."
  ;; Config
  (name    "ghost"  :type string)
  (version "0.1.0" :type string)
  (command nil)              ; list of strings: the server subprocess command
  ;; Connection (set during connect)
  (process nil)              ; uiop:process-info
  (stdin   nil)              ; stream: write requests here
  (stdout  nil)              ; stream: read responses from here
  (reader-thread nil)        ; bt:thread
  ;; Protocol state
  (next-id      0)           ; incremented under pending-lock
  (pending      (make-hash-table :test #'eql))  ; id → pending-request
  (pending-lock (bt:make-lock "mcp-pending"))
  ;; Session state (set during handshake)
  (server-info         nil)  ; alist: name, version
  (server-capabilities nil)  ; alist: from initialize response
  (connected-p         nil))

;;; ──────────────────────────────────────────────────────────────────────────
;;; Public constructor
;;; ──────────────────────────────────────────────────────────────────────────

(defun make-client (&key (name "ghost") (version "0.1.0") command)
  "Create an unconnected MCP client. Call connect to establish a session.
   COMMAND is a list of strings, e.g. '(\"npx\" \"@modelcontextprotocol/server-filesystem\" \"/tmp\")."
  (make-mcp-client :name name :version version :command command))

;;; ──────────────────────────────────────────────────────────────────────────
;;; Internal: request sending and reader thread
;;; ──────────────────────────────────────────────────────────────────────────

(defun %next-id (client)
  "Return the next request ID (thread-safe)."
  (bt:with-lock-held ((client-pending-lock client))
    (incf (client-next-id client))))

(defun %send-request (client method params &key (timeout 30))
  "Send a JSON-RPC request and block until the response arrives.
   Registers the promise BEFORE writing to avoid a response-before-register race."
  (let* ((id      (%next-id client))
         (request (make-request :id id :method method :params params))
         (promise (make-pending-request)))
    ;; Register before sending
    (bt:with-lock-held ((client-pending-lock client))
      (setf (gethash id (client-pending client)) promise))
    ;; Write to server stdin
    (write-string (encode-request request) (client-stdin client))
    (write-char #\Newline (client-stdin client))
    (force-output (client-stdin client))
    ;; Block until reader thread fulfills promise
    (unwind-protect
        (await-promise promise :timeout timeout)
      (bt:with-lock-held ((client-pending-lock client))
        (remhash id (client-pending client))))))

(defun %send-notification (client method params)
  "Send a JSON-RPC notification (no response expected)."
  (let ((notif (make-notification :method method :params params)))
    (write-string (encode-request notif) (client-stdin client))
    (write-char #\Newline (client-stdin client))
    (force-output (client-stdin client))))

(defun %dispatch-response (client response)
  "Route a response to the waiting caller. Called from reader thread.
   Extracts the promise under pending-lock, then fulfills it outside
   the lock to avoid lock-ordering inversion with await-promise."
  (let* ((id      (response-id response))
         (promise (bt:with-lock-held ((client-pending-lock client))
                    (gethash id (client-pending client)))))
    (when promise
      (fulfill-promise promise response))))

(defun %abort-all-pending (client message)
  "Fulfill all pending requests with a session-closed error. Called on EOF.
   Collects promises under pending-lock, clears the table, then fulfills
   outside the lock to avoid lock-ordering inversion with await-promise."
  (let (promises)
    (bt:with-lock-held ((client-pending-lock client))
      (maphash (lambda (id promise)
                 (declare (ignore id))
                 (push promise promises))
               (client-pending client))
      (clrhash (client-pending client)))
    (let ((error-response (make-error-response
                           :id nil :code -32603 :message message)))
      (dolist (promise promises)
        (fulfill-promise promise error-response)))))

(defun %reader-loop (client)
  "Read server stdout in a loop, dispatching responses and ignoring notifications.
   Exits cleanly on EOF. Called in the reader thread."
  (handler-case
      (loop
        (let ((line (read-line (client-stdout client) nil nil)))
          (unless line
            ;; EOF: server exited — protect connected-p write under pending-lock
            (bt:with-lock-held ((client-pending-lock client))
              (setf (client-connected-p client) nil))
            (%abort-all-pending client "MCP session closed: server exited (EOF)")
            (return))
          (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
            (when (plusp (length trimmed))
              ;; Narrow to expected parse failures; let programming errors propagate
              (handler-case
                  (let ((msg (parse-client-message trimmed)))
                    (typecase msg
                      (json-rpc-response
                       (%dispatch-response client msg))
                      (json-rpc-request
                       ;; Server notification — ignore for now
                       nil)))
                (parse-error () nil)
                (invalid-request () nil))))))
    (error ()
      ;; Unexpected error in reader thread — mark disconnected
      (bt:with-lock-held ((client-pending-lock client))
        (setf (client-connected-p client) nil))
      (%abort-all-pending client "MCP session closed: reader thread error"))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; connect / disconnect
;;; ──────────────────────────────────────────────────────────────────────────

(defun connect (client)
  "Spawn the server subprocess and perform the MCP initialization handshake.
   Starts the reader thread. Returns CLIENT (mutated).
   Signals mcp-connect-error if the subprocess fails to start or handshake fails."
  (handler-case
      (let ((process (uiop:launch-program
                      (client-command client)
                      :input :stream
                      :output :stream
                      :error-output nil)))
        (setf (client-process client) process
              (client-stdin  client) (uiop:process-info-input process)
              (client-stdout client) (uiop:process-info-output process))
        ;; Start reader thread before handshake so responses can be received
        (setf (client-reader-thread client)
              (bt:make-thread
               (lambda () (%reader-loop client))
               :name "mcp-reader"
               :initial-bindings nil))
        (%do-handshake client)
        (bt:with-lock-held ((client-pending-lock client))
          (setf (client-connected-p client) t))
        client)
    (mcp-session-closed (c)
      ;; Handshake timed out — clean up and re-signal as connect error
      (ignore-errors (disconnect client))
      (error 'mcp-connect-error
             :command (client-command client)
             :message (format nil "Handshake failed: ~a" (error-message c))))
    (error (e)
      (ignore-errors (disconnect client))
      (error 'mcp-connect-error
             :command (client-command client)
             :message (format nil "~a" e)))))

(defun %do-handshake (client)
  "Send initialize, store capabilities, send notifications/initialized."
  (let ((response (%send-request
                   client "initialize"
                   `(("protocolVersion" . "2025-11-25")
                     ("capabilities"   . ,(make-hash-table :test #'equal))
                     ("clientInfo"     . (("name"    . ,(client-name client))
                                          ("version" . ,(client-version client))))))))
    ;; Check for error before touching result — error response has nil result
    (when (response-error response)
      (error 'mcp-session-closed
             :message (format nil "initialize rejected: ~a"
                               (getf (response-error response) :message))))
    (let ((result (response-result response)))
      (setf (client-server-info client)
            (cdr (assoc "serverInfo" result :test #'string=)))
      (setf (client-server-capabilities client)
            (cdr (assoc "capabilities" result :test #'string=)))))
  (%send-notification client "notifications/initialized" nil))

(defun disconnect (client &key (timeout 5))
  "Shut down the MCP session cleanly.
   Closes server stdin, waits for the reader thread to exit, kills if needed."
  (bt:with-lock-held ((client-pending-lock client))
    (setf (client-connected-p client) nil))
  ;; Close stdin → server sees EOF and exits
  (when (client-stdin client)
    (ignore-errors (close (client-stdin client)))
    (setf (client-stdin client) nil))
  ;; Wait for reader thread; bt:join-thread has no :timeout in bt1 API,
  ;; so wrap with bt:with-timeout which signals bt:timeout on expiry.
  (when (client-reader-thread client)
    (handler-case
        (bt:with-timeout (timeout)
          (bt:join-thread (client-reader-thread client)))
      (bt:timeout ()
        (ignore-errors
          (bt:destroy-thread (client-reader-thread client)))))
    (setf (client-reader-thread client) nil))
  ;; Kill process if still alive
  (when (client-process client)
    (ignore-errors (uiop:terminate-process (client-process client)))
    (setf (client-process client) nil))
  t)

;;; ──────────────────────────────────────────────────────────────────────────
;;; list-tools
;;; ──────────────────────────────────────────────────────────────────────────

(defun list-tools (client)
  "List all tools available on the connected MCP server.
   Handles pagination automatically.
   Returns a list of plists: (:name NAME :description DESC :input-schema SCHEMA)."
  (loop
    with cursor = nil
    with all-tools = '()
    do (let* ((params (if cursor
                          `(("cursor" . ,cursor))
                          '()))
              (response (%send-request client "tools/list" params))
              (result   (response-result response))
              (tools    (cdr (assoc "tools" result :test #'string=)))
              (next     (cdr (assoc "nextCursor" result :test #'string=))))
         (dolist (tool tools)
           (push (list :name         (cdr (assoc "name"        tool :test #'string=))
                       :description  (cdr (assoc "description" tool :test #'string=))
                       :input-schema (cdr (assoc "inputSchema" tool :test #'string=)))
                 all-tools))
         (if next
             (setf cursor next)
             (return (nreverse all-tools))))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; call-tool
;;; ──────────────────────────────────────────────────────────────────────────

(defun call-tool (client name arguments)
  "Call a tool on the MCP server.
   NAME is a string. ARGUMENTS is an alist or hash-table.
   Returns a plist: (:content CONTENT :is-error BOOL).
   Signals mcp-tool-error if the server returns isError:true."
  (let* ((params   `(("name"      . ,name)
                     ("arguments" . ,(or arguments
                                        (make-hash-table :test #'equal)))))
         (response (%send-request client "tools/call" params))
         (err      (response-error response)))
    ;; Protocol-level error (method not found, invalid params, etc.)
    ;; Session is still alive — use mcp-protocol-error, not mcp-session-closed
    (when err
      (error 'mcp-protocol-error
             :message (format nil "tools/call failed: ~a"
                               (getf err :message))))
    (let* ((result   (response-result response))
           (content  (cdr (assoc "content"  result :test #'string=)))
           (is-error (cdr (assoc "isError"  result :test #'string=))))
      (when is-error
        (restart-case
            (error 'mcp-tool-error
                   :tool-name name
                   :content   content
                   :message   (format nil "Tool ~a returned an error" name))
          (use-value (v)
            :report "Return a specific value instead"
            :interactive (lambda ()
                           (format t "Return value: ")
                           (list (read)))
            (return-from call-tool (list :content v :is-error nil)))
          (skip-tool ()
            :report "Return nil content (skip tool result)"
            (return-from call-tool (list :content nil :is-error t)))))
      (list :content content :is-error nil))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; with-mcp-client macro
;;; ──────────────────────────────────────────────────────────────────────────

(defmacro with-mcp-client ((var &rest make-args) &body body)
  "Connect an MCP client for the duration of BODY, disconnect on exit.
   VAR is bound to the connected client.
   MAKE-ARGS are passed to make-client (keyword args: :name :version :command).
   disconnect is called even if connect signals — safe because disconnect
   guards every slot with (when ...)."
  `(let ((,var (cl-mcp.client:make-client ,@make-args)))
     (unwind-protect
         (progn
           (cl-mcp.client:connect ,var)
           ,@body)
       (cl-mcp.client:disconnect ,var))))
