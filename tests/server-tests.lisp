;;; tests/server-tests.lisp
;;; ABOUTME: Tests for MCP server protocol dispatch

(in-package #:cl-mcp-tests)

(def-suite server-tests
  :description "MCP server tests"
  :in cl-mcp-tests)

(in-suite server-tests)

;;; Helpers

(defun make-test-server ()
  "Create a server with a simple echo tool for testing."
  (let ((server (cl-mcp:make-server :name "test-server" :version "0.1.0")))
    (cl-mcp:register-tool server "echo"
      :description "Echo the input text"
      :schema '(("type" . "object")
                ("required" . ("text"))
                ("properties" . (("text" . (("type" . "string")
                                            ("description" . "Text to echo"))))))
      :handler (lambda (args)
                 (cdr (assoc "text" args :test #'string=))))
    server))

(defun send-json (server json-string)
  "Send a JSON string to server and return the response JSON string.
May return multiple lines if multiple requests are sent."
  (let ((input (make-string-input-stream (format nil "~a~%" json-string)))
        (output (make-string-output-stream)))
    (cl-mcp:run-server server :input input :output output)
    (string-trim '(#\Newline #\Space) (get-output-stream-string output))))

(defun parse-response (json-string)
  "Parse a JSON response string to an alist."
  (yason:parse json-string :object-as :alist))

(defun split-response-lines (output-str)
  "Split output into non-empty response lines."
  (remove-if (lambda (s) (zerop (length s)))
             (loop with start = 0
                   for end = (position #\Newline output-str :start start)
                   collect (subseq output-str start (or end (length output-str)))
                   while end
                   do (setf start (1+ end)))))

;;; Initialize tests

(test server-initialize
  "Server responds to initialize with server info"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"))
         (response (parse-response response-json)))
    (is (string= "2.0" (cdr (assoc "jsonrpc" response :test #'string=))))
    (is (= 1 (cdr (assoc "id" response :test #'string=))))
    (let ((result (cdr (assoc "result" response :test #'string=))))
      (is (assoc "serverInfo" result :test #'string=))
      (is (assoc "capabilities" result :test #'string=))
      (is (assoc "protocolVersion" result :test #'string=))
      (let ((info (cdr (assoc "serverInfo" result :test #'string=))))
        (is (string= "test-server" (cdr (assoc "name" info :test #'string=))))
        (is (string= "0.1.0" (cdr (assoc "version" info :test #'string=))))))))

;;; Tools/list tests

(test server-tools-list
  "Server responds to tools/list with registered tools"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}"))
         (response (parse-response response-json)))
    (let* ((result (cdr (assoc "result" response :test #'string=)))
           (tools (cdr (assoc "tools" result :test #'string=))))
      (is (= 1 (length tools)))
      (let ((tool (first tools)))
        (is (string= "echo" (cdr (assoc "name" tool :test #'string=))))))))

;;; Tools/call tests

(test server-tools-call
  "Server dispatches tools/call to handler"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"text\":\"hello\"}}}"))
         (response (parse-response response-json)))
    (is (null (assoc "error" response :test #'string=)))
    (let* ((result (cdr (assoc "result" response :test #'string=)))
           (content (cdr (assoc "content" result :test #'string=)))
           (block (first content)))
      (is (string= "text" (cdr (assoc "type" block :test #'string=))))
      (is (string= "hello" (cdr (assoc "text" block :test #'string=)))))))

(test server-tools-call-unknown
  "Server returns error for unknown tool"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"nonexistent\",\"arguments\":{}}}"))
         (response (parse-response response-json)))
    (let ((err (cdr (assoc "error" response :test #'string=))))
      (is (not (null err)))
      (is (= -32601 (cdr (assoc "code" err :test #'string=)))))))

(test server-tools-call-missing-args
  "Server returns error for missing required args"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{}}}"))
         (response (parse-response response-json)))
    (let ((err (cdr (assoc "error" response :test #'string=))))
      (is (not (null err)))
      (is (= -32602 (cdr (assoc "code" err :test #'string=)))))))

;;; Unknown method test

(test server-unknown-method
  "Server returns error for unknown method"
  (let* ((server (make-test-server))
         (response-json (send-json server
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unknown/method\",\"params\":{}}"))
         (response (parse-response response-json)))
    (let ((err (cdr (assoc "error" response :test #'string=))))
      (is (not (null err)))
      (is (= -32601 (cdr (assoc "code" err :test #'string=)))))))

;;; Notification test

(test server-notification-no-response
  "Notifications produce no response"
  (let ((server (make-test-server))
        (input (make-string-input-stream
                (format nil "~a~%~a~%"
                        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")))
        (output (make-string-output-stream)))
    (cl-mcp:run-server server :input input :output output)
    (let ((lines (split-response-lines (get-output-stream-string output))))
      ;; Only 1 response (for initialize), not 2
      (is (= 1 (length lines))))))

;;; Error recovery test

(test server-survives-handler-error
  "Server continues after handler error"
  (let ((server (cl-mcp:make-server :name "test" :version "0.1.0")))
    (cl-mcp:register-tool server "boom"
      :description "Always errors"
      :schema '(("type" . "object"))
      :handler (lambda (args) (declare (ignore args)) (error "kaboom")))
    (cl-mcp:register-tool server "ok"
      :description "Always works"
      :schema '(("type" . "object"))
      :handler (lambda (args) (declare (ignore args)) "fine"))
    (let ((input (make-string-input-stream
                  (format nil "~a~%~a~%"
                          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"boom\",\"arguments\":{}}}"
                          "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"ok\",\"arguments\":{}}}")))
          (output (make-string-output-stream)))
      (cl-mcp:run-server server :input input :output output)
      (let ((lines (split-response-lines (get-output-stream-string output))))
        ;; Both requests get responses
        (is (= 2 (length lines)))
        ;; First is error, second is success
        (let ((resp1 (yason:parse (first lines) :object-as :alist))
              (resp2 (yason:parse (second lines) :object-as :alist)))
          (is (not (null (assoc "error" resp1 :test #'string=))))
          (is (null (assoc "error" resp2 :test #'string=))))))))

;;; Full session test

(test server-full-session
  "Full MCP session: initialize -> notification -> tools/list -> tools/call"
  (let ((server (make-test-server)))
    (let ((input (make-string-input-stream
                  (format nil "~{~a~%~}"
                          '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
                            "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}"
                            "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"text\":\"hello\"}}}"))))
          (output (make-string-output-stream)))
      (cl-mcp:run-server server :input input :output output)
      (let ((lines (split-response-lines (get-output-stream-string output))))
        ;; 3 responses: initialize, tools/list, tools/call
        ;; Notification produces no response
        (is (= 3 (length lines)))))))
