;;; cl-mcp.asd
;;; ABOUTME: ASDF system definition for cl-mcp

(asdf:defsystem #:cl-mcp
  :description "Model Context Protocol server framework for Common Lisp"
  :author "Abhijit Rao <quasi@quasilabs.com>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:yason
               #:opsis/conditions)
  :components ((:module "src"
                :components
                ((:file "packages")
                 (:file "conditions")
                 (:file "json-rpc")
                 (:file "transport")
                 (:file "tools")
                 (:file "server"))))
  :in-order-to ((asdf:test-op (asdf:test-op #:cl-mcp/tests))))

(asdf:defsystem #:cl-mcp/tests
  :description "Tests for cl-mcp"
  :depends-on (#:cl-mcp
               #:fiveam)
  :components ((:module "tests"
                :components
                ((:file "packages")
                 (:file "conditions-tests")
                 (:file "json-rpc-tests")
                 (:file "encoding-tests")
                 (:file "transport-tests")
                 (:file "tools-tests")
                 (:file "server-tests"))))
  :perform (asdf:test-op (o c)
             (uiop:symbol-call :fiveam :run! :cl-mcp-tests)))
