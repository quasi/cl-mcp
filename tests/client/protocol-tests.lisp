;;; tests/client/protocol-tests.lisp
;;; ABOUTME: Tests for encode-request, parse-client-message, pending-request

(in-package #:cl-mcp-client-tests)

(def-suite client-protocol-tests
  :description "Client protocol encoding/parsing tests"
  :in cl-mcp-client-tests)

(in-suite client-protocol-tests)

;;; encode-request

(test encode-request-produces-jsonrpc-field
  "encode-request output has jsonrpc:2.0"
  (let* ((req (cl-mcp.json-rpc:make-request :id 1 :method "ping" :params nil))
         (json (cl-mcp.client:encode-request req))
         (parsed (yason:parse json :object-as :alist)))
    (is (string= "2.0" (cdr (assoc "jsonrpc" parsed :test #'string=))))))

(test encode-request-includes-id
  "encode-request includes id field for requests"
  (let* ((req (cl-mcp.json-rpc:make-request :id 42 :method "tools/list" :params nil))
         (json (cl-mcp.client:encode-request req))
         (parsed (yason:parse json :object-as :alist)))
    (is (= 42 (cdr (assoc "id" parsed :test #'string=))))))

(test encode-request-omits-id-for-notification
  "encode-request omits id for notifications"
  (let* ((notif (cl-mcp.json-rpc:make-notification :method "notifications/initialized"))
         (json (cl-mcp.client:encode-request notif))
         (parsed (yason:parse json :object-as :alist)))
    (is (null (assoc "id" parsed :test #'string=)))))

(test encode-request-includes-method
  "encode-request includes the method"
  (let* ((req (cl-mcp.json-rpc:make-request :id 1 :method "tools/list" :params nil))
         (json (cl-mcp.client:encode-request req))
         (parsed (yason:parse json :object-as :alist)))
    (is (string= "tools/list" (cdr (assoc "method" parsed :test #'string=))))))

(test encode-request-omits-params-when-nil
  "encode-request omits params field when params is nil"
  (let* ((req (cl-mcp.json-rpc:make-request :id 1 :method "ping" :params nil))
         (json (cl-mcp.client:encode-request req))
         (parsed (yason:parse json :object-as :alist)))
    (is (null (assoc "params" parsed :test #'string=)))))

(test encode-request-includes-params-when-present
  "encode-request includes params when non-nil"
  (let* ((req (cl-mcp.json-rpc:make-request
               :id 1 :method "tools/call"
               :params '(("name" . "echo") ("arguments" . (("text" . "hi"))))))
         (json (cl-mcp.client:encode-request req))
         (parsed (yason:parse json :object-as :alist)))
    (is (not (null (assoc "params" parsed :test #'string=))))))

(test encode-request-no-trailing-newline
  "encode-request returns string without trailing newline"
  (let* ((req (cl-mcp.json-rpc:make-request :id 1 :method "ping" :params nil))
         (json (cl-mcp.client:encode-request req)))
    (is (char/= #\Newline (char json (1- (length json)))))))

;;; parse-client-message

(test parse-client-message-success-response
  "parse-client-message returns json-rpc-response for success responses"
  (let* ((json "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"value\":42}}")
         (msg (cl-mcp.client:parse-client-message json)))
    (is (typep msg 'cl-mcp.json-rpc:json-rpc-response))
    (is (= 1 (cl-mcp.json-rpc:response-id msg)))
    (is (null (cl-mcp.json-rpc:response-error msg)))))

(test parse-client-message-error-response
  "parse-client-message returns json-rpc-response for error responses"
  (let* ((json "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"not found\"}}")
         (msg (cl-mcp.client:parse-client-message json)))
    (is (typep msg 'cl-mcp.json-rpc:json-rpc-response))
    (is (= 1 (cl-mcp.json-rpc:response-id msg)))
    (is (= -32601 (getf (cl-mcp.json-rpc:response-error msg) :code)))))

(test parse-client-message-server-notification
  "parse-client-message returns json-rpc-request for server notifications"
  (let* ((json "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}")
         (msg (cl-mcp.client:parse-client-message json)))
    (is (typep msg 'cl-mcp.json-rpc:json-rpc-request))
    (is (string= "notifications/tools/list_changed"
                 (cl-mcp.json-rpc:request-method msg)))))

(test parse-client-message-signals-on-bad-json
  "parse-client-message signals parse-error on invalid JSON"
  (signals cl-mcp.conditions:parse-error
    (cl-mcp.client:parse-client-message "{not valid")))

;;; ID generator

(test id-generator-produces-sequential-ids
  "make-id-generator returns sequential positive integers"
  (let ((gen (cl-mcp.client:make-id-generator)))
    (is (= 1 (funcall gen)))
    (is (= 2 (funcall gen)))
    (is (= 3 (funcall gen)))))

(test id-generators-are-independent
  "Two generators have independent counters"
  (let ((g1 (cl-mcp.client:make-id-generator))
        (g2 (cl-mcp.client:make-id-generator)))
    (is (= 1 (funcall g1)))
    (is (= 1 (funcall g2)))
    (is (= 2 (funcall g1)))))

;;; pending-request

(test pending-request-starts-unfulfilled
  "A new pending-request is not done"
  (let ((p (cl-mcp.client:make-pending-request)))
    (is (null (cl-mcp.client:pending-request-done p)))))

(test fulfill-promise-marks-done
  "fulfill-promise sets done and stores result"
  (let ((p (cl-mcp.client:make-pending-request))
        (resp (cl-mcp.json-rpc:make-success-response :id 1 :result '(("ok" . t)))))
    (cl-mcp.client:fulfill-promise p resp)
    (is (cl-mcp.client:pending-request-done p))
    (is (eq resp (cl-mcp.client:pending-request-result p)))))
