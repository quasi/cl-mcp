;;; tests/client/client-tests.lisp
;;; ABOUTME: Integration tests for mcp-client — spawns a real subprocess

(in-package #:cl-mcp-client-tests)

(def-suite client-integration-tests
  :description "Client integration tests (spawns subprocess)"
  :in cl-mcp-client-tests)

(in-suite client-integration-tests)

;;; Helpers

(defun test-server-asd-path ()
  "Absolute path to cl-mcp.asd for the test server subprocess."
  (namestring (truename (asdf:system-source-file :cl-mcp))))

(defun test-server-script-path ()
  "Absolute path to the test server script."
  (namestring
   (merge-pathnames "tests/client/test-server.lisp"
                    (asdf:system-source-directory :cl-mcp))))

(defun %make-test-client ()
  "Create an mcp-client pointing at the test server subprocess."
  (cl-mcp.client:make-client
   :name "test-client"
   :version "0.1.0"
   :command (list "sbcl"
                  "--non-interactive"
                  "--load" (test-server-asd-path)
                  "--load" (test-server-script-path))))

;;; make-client

(test make-client-creates-unconnected-client
  "make-client returns a disconnected client"
  (let ((c (cl-mcp.client:make-client
            :name "test" :version "0.1.0" :command '("echo" "hi"))))
    (is (not (cl-mcp.client:client-connected-p c)))
    (is (string= "test" (cl-mcp.client:client-name c)))
    (is (string= "0.1.0" (cl-mcp.client:client-version c)))))

;;; connect / disconnect

(test connect-establishes-session
  "connect spawns subprocess, does handshake, sets connected-p"
  (let ((c (%make-test-client)))
    (unwind-protect
        (progn
          (cl-mcp.client:connect c)
          (is (cl-mcp.client:client-connected-p c))
          (is (not (null (cl-mcp.client:client-server-info c)))))
      (cl-mcp.client:disconnect c))))

(test connect-stores-server-info
  "connect stores server name and version from initialize response"
  (let ((c (%make-test-client)))
    (unwind-protect
        (progn
          (cl-mcp.client:connect c)
          (let ((info (cl-mcp.client:client-server-info c)))
            (is (not (null info)))
            (is (string= "test-server"
                         (cdr (assoc "name" info :test #'string=))))))
      (cl-mcp.client:disconnect c))))

(test disconnect-sets-connected-p-nil
  "disconnect sets connected-p to nil"
  (let ((c (%make-test-client)))
    (cl-mcp.client:connect c)
    (cl-mcp.client:disconnect c)
    (is (not (cl-mcp.client:client-connected-p c)))))

;;; with-mcp-client

(test with-mcp-client-disconnects-on-exit
  "with-mcp-client ensures disconnect even without error"
  (let (saved-client)
    (cl-mcp.client:with-mcp-client (c :name "test" :version "0.1.0"
                                       :command (list "sbcl" "--non-interactive"
                                                      "--load" (test-server-asd-path)
                                                      "--load" (test-server-script-path)))
      (setf saved-client c)
      (is (cl-mcp.client:client-connected-p c)))
    (is (not (cl-mcp.client:client-connected-p saved-client)))))

;;; list-tools

(test list-tools-returns-tool-list
  "list-tools returns a list with at least one tool"
  (cl-mcp.client:with-mcp-client (c :name "test" :version "0.1.0"
                                     :command (list "sbcl" "--non-interactive"
                                                    "--load" (test-server-asd-path)
                                                    "--load" (test-server-script-path)))
    (let ((tools (cl-mcp.client:list-tools c)))
      (is (listp tools))
      (is (>= (length tools) 1)))))

(test list-tools-returns-tool-names
  "list-tools returns plists with :name key"
  (cl-mcp.client:with-mcp-client (c :name "test" :version "0.1.0"
                                     :command (list "sbcl" "--non-interactive"
                                                    "--load" (test-server-asd-path)
                                                    "--load" (test-server-script-path)))
    (let ((tools (cl-mcp.client:list-tools c)))
      (let ((names (mapcar (lambda (tool) (getf tool :name)) tools)))
        (is (member "echo" names :test #'string=))))))

;;; call-tool

(test call-tool-returns-result
  "call-tool sends tools/call and returns content"
  (cl-mcp.client:with-mcp-client (c :name "test" :version "0.1.0"
                                     :command (list "sbcl" "--non-interactive"
                                                    "--load" (test-server-asd-path)
                                                    "--load" (test-server-script-path)))
    (let ((result (cl-mcp.client:call-tool c "echo" '(("msg" . "hello")))))
      (is (not (null result)))
      (is (not (getf result :is-error))))))

(test call-tool-result-has-content
  "call-tool result contains the tool output"
  (cl-mcp.client:with-mcp-client (c :name "test" :version "0.1.0"
                                     :command (list "sbcl" "--non-interactive"
                                                    "--load" (test-server-asd-path)
                                                    "--load" (test-server-script-path)))
    (let* ((result (cl-mcp.client:call-tool c "echo" '(("msg" . "world"))))
           (content (getf result :content)))
      (is (not (null content)))
      ;; Content is a list; first item has the text
      (let ((first-block (first content)))
        (is (string= "world"
                     (cdr (assoc "text" first-block :test #'string=))))))))
