;;; src/client/protocol.lisp
;;; ABOUTME: Client-side JSON-RPC encoding, response parsing, pending-request machinery

(in-package #:cl-mcp.client)

;;; ──────────────────────────────────────────────────────────────────────────
;;; encode-request — complement of cl-mcp.json-rpc:encode-response
;;; ──────────────────────────────────────────────────────────────────────────

(defun encode-request (request)
  "Encode a json-rpc-request to a JSON string (no trailing newline).
   Works for both requests (with id) and notifications (id nil)."
  (with-output-to-string (s)
    (let ((ht (make-hash-table :test #'equal)))
      (setf (gethash "jsonrpc" ht) "2.0")
      (setf (gethash "method" ht) (request-method request))
      (when (request-id request)
        (setf (gethash "id" ht) (request-id request)))
      (when (request-params request)
        (setf (gethash "params" ht)
              (convert-for-json (request-params request))))
      (yason:encode ht s))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; parse-client-message — complement of cl-mcp.json-rpc:parse-message
;;; ──────────────────────────────────────────────────────────────────────────

(defun parse-client-message (json-string)
  "Parse an incoming JSON-RPC message from an MCP server.
   Returns json-rpc-response for responses (has result or error field).
   Returns json-rpc-request for server notifications (has method field).
   Signals parse-error on invalid JSON."
  (let ((data (handler-case
                  (yason:parse json-string :object-as :alist)
                (error (e)
                  (error 'parse-error
                         :message (format nil "~a" e))))))
    (%dispatch-incoming data)))

(defun %dispatch-incoming (data)
  "Dispatch a parsed alist to the appropriate struct based on fields present."
  (cond
    ;; Has "method" → server notification (treat as json-rpc-request)
    ((assoc "method" data :test #'string=)
     (make-notification :method (cdr (assoc "method" data :test #'string=))
                        :params (cdr (assoc "params" data :test #'string=))))
    ;; Has "result" → success response
    ((assoc "result" data :test #'string=)
     (make-success-response
      :id     (cdr (assoc "id" data :test #'string=))
      :result (cdr (assoc "result" data :test #'string=))))
    ;; Has "error" → error response
    ((assoc "error" data :test #'string=)
     (let ((err (cdr (assoc "error" data :test #'string=))))
       (make-error-response
        :id      (cdr (assoc "id" data :test #'string=))
        :code    (cdr (assoc "code" err :test #'string=))
        :message (cdr (assoc "message" err :test #'string=))
        :data    (cdr (assoc "data" err :test #'string=)))))
    (t
     (error 'invalid-request
            :message "Message has neither method nor result/error"))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; ID generator — thread-safe counter
;;; ──────────────────────────────────────────────────────────────────────────

(defun make-id-generator ()
  "Return a thread-safe function that produces sequential integer IDs starting at 1."
  (let ((counter 0)
        (lock (bt:make-lock "mcp-id-generator")))
    (lambda ()
      (bt:with-lock-held (lock)
        (incf counter)))))

;;; ──────────────────────────────────────────────────────────────────────────
;;; pending-request — one-shot promise for correlating responses to requests
;;; ──────────────────────────────────────────────────────────────────────────

(defstruct pending-request
  "One-shot promise that correlates an outgoing request to its response.
   The reader thread fulfills it; the calling thread awaits it."
  (lock   (bt:make-lock "pending-request") :read-only t)
  (condvar (bt:make-condition-variable)    :read-only t)
  (result nil)
  (done   nil))

(defun fulfill-promise (promise result)
  "Fulfill a pending-request with RESULT. Called from the reader thread."
  (bt:with-lock-held ((pending-request-lock promise))
    (setf (pending-request-result promise) result)
    (setf (pending-request-done promise) t)
    (bt:condition-notify (pending-request-condvar promise))))

(defun await-promise (promise &key (timeout 30))
  "Block the calling thread until PROMISE is fulfilled.
   Returns the result. Signals mcp-session-closed on timeout."
  (bt:with-lock-held ((pending-request-lock promise))
    (loop until (pending-request-done promise)
          do (unless (bt:condition-wait
                      (pending-request-condvar promise)
                      (pending-request-lock promise)
                      :timeout timeout)
               (error 'mcp-session-closed
                      :message (format nil "Timeout (~as) waiting for server response"
                                       timeout)))))
  (pending-request-result promise))
