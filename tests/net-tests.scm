;; HTTP request errors and connection teardown, using a loopback listener.

(import (scheme base) (scheme write) (scheme time)
        (chibi test) (chibi net) (chibi net http-server)
        (chibi net servlet) (chibi filesystem) (chibi process)
        (only (srfi 130) string-prefix? string-suffix?) (srfi 18))

;; Retry binds rather than depending on a fixed port being unused.
(define (test-listener)
  (let lp ((port (+ 10000 (modulo (current-process-id) 20000))) (tries 100))
    (let ((sock (guard (exn (else #f))
                  (make-listener-socket (get-address-info "127.0.0.1" port)))))
      (cond
       (sock (cons sock port))
       ((positive? tries) (lp (+ port 1) (- tries 1)))
       (else (error "could not bind a loopback test listener"))))))

(define (read-response sock)
  (let ((buffer (make-bytevector 1024))
        (out (open-output-bytevector))
        (deadline (+ (current-second) 3)))
    (let lp ()
      (let* ((remaining (- deadline (current-second)))
             (n (and (positive? remaining)
                     (receive!/non-blocking sock buffer remaining))))
        (cond
         ((or (not n) (negative? n))
          (list #f (utf8->string (get-output-bytevector out))))
         ((zero? n) (list #t (utf8->string (get-output-bytevector out))))
         (else
          (write-bytevector buffer out 0 n)
          (lp)))))))

(define (exchange port bytes half-close? inspect)
  (let* ((io (open-net-io "127.0.0.1" port))
         (sock (car io)) (in (cadr io)) (out (car (cddr io))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (write-bytevector bytes out)
        (flush-output-port out)
        (if half-close? (close-output-port out))
        (inspect (read-response sock)))
      (lambda ()
        (close-output-port out)
        (close-input-port in)
        (close-file-descriptor sock)))))

(define (post target body)
  (string->utf8
   (string-append "POST " target " HTTP/1.1\r\nHost: localhost\r\n"
                  "Content-Length: " (number->string (string-length body))
                  "\r\nConnection: close\r\n\r\n" body)))

(define last-request #f)
(define calls 0)
(define (reject-post cfg request next restart)
  (set! last-request request)
  (set! calls (+ calls 1))
  (if (equal? "/raise" (request-path request))
      (error "deliberate servlet failure")
      (begin
        (servlet-respond request 404 "Not Found" '((Content-Length . "8")))
        (servlet-write request "rejected"))))

(define (check-response port target expected)
  (exchange port (post target "") #t
    (lambda (response)
      (test-assert "orderly response EOF" (car response))
      (test-assert target
        (string-prefix? (string-append "HTTP/1.1 " expected " ")
                        (cadr response))))))

(define (wait-for-input-close request)
  (let ((deadline (+ (current-second) 3)))
    (let lp ()
      (cond
       ((not (input-port-open? (request-in request))) #t)
       ((>= (current-second) deadline) #f)
       (else (thread-sleep! 0.01) (lp))))))

(test-begin "HTTP server")
(let* ((listener (test-listener))
       (port (cdr listener))
       (server (make-thread (lambda () (run-http-server (car listener) reject-post)))))
  (dynamic-wind
    (lambda () (thread-start! server))
    (lambda ()
      (check-response port "/" "404")
      (check-response port "/?a&b=c" "404")
      (test '(("a" . #f) ("b" . "c")) (request-params last-request))
      (check-response port "/?&" "404")
      (test '(("" . #f)) (request-params last-request))
      (let ((before calls))
        (for-each (lambda (target) (check-response port target "400"))
                  '("/?x=%GG" "/?x=%G0" "/?x=%0G" "/?%GG=x"))
        (test "malformed queries do not invoke the servlet" before calls))
      (check-response port "/raise" "500")
      (exchange port (string->utf8 "POST /\r\nHost: localhost\r\n\r\n") #t
        (lambda (response)
          (test-assert "bad request line returns 400"
            (string-prefix? "HTTP/1.1 400 " (cadr response)))))
      (exchange port (post "/" (make-string 8192 #\x)) #t
        (lambda (response)
          (test-assert "unread POST body does not reset the connection" (car response))
          (test-assert "rejection body arrives in full"
            (string-suffix? "rejected" (cadr response)))))
      (exchange port (post "/" (make-string 131072 #\x)) #t
        (lambda (response)
          (test-assert "large unread POST body does not reset the connection"
            (car response))
          (test-assert "large rejected upload still receives the response"
            (string-suffix? "rejected" (cadr response)))))
      (exchange port (post "/" "") #f
        (lambda (response)
          (test-assert "response finishes while the peer can still write" (car response))
          (test-assert "an idle peer cannot prevent connection cleanup"
            (wait-for-input-close last-request))))
      (check-response port "/" "404"))
    (lambda ()
      (thread-terminate! server)
      (close-file-descriptor (car listener)))))
(test-end)
(test-exit)
