
(load-relative "loadtest.rktl")

(Section 'prompt)

;; ----------------------------------------

(define (test-breaks-ok)
  (err/rt-test (break-thread (current-thread)) exn:break?))


(test (void) call-with-continuation-prompt void)
(test (void) call-with-continuation-prompt void (default-continuation-prompt-tag))
(test (void) call-with-continuation-prompt void (default-continuation-prompt-tag) list)
(test '() call-with-continuation-prompt list (default-continuation-prompt-tag) void)
(test '(1) call-with-continuation-prompt list (default-continuation-prompt-tag) void 1)
(test '(1 2) call-with-continuation-prompt list (default-continuation-prompt-tag) void 1 2)
(test '(1 2 3) call-with-continuation-prompt list (default-continuation-prompt-tag) void 1 2 3)
(test '(1 2 3 4 5 6 7 8 9 10) call-with-continuation-prompt list (default-continuation-prompt-tag) void 
      1 2 3 4 5 6 7 8 9 10)

;;----------------------------------------
;; cc variants

(define call/cc-via-composable 
  (case-lambda 
   [(f) (call/cc-via-composable f (default-continuation-prompt-tag))]
   [(f tag)
    (call-with-composable-continuation
     (lambda (k)
       (f (lambda vs
            (abort-current-continuation 
             tag 
             (lambda () 
               (call-with-continuation-prompt
                (lambda ()
                  (apply k vs))
                tag
                (lambda (thunk) (thunk)))))))))]))
                                           
(define call/cc-via-aborted-and-restored-composable 
  (case-lambda 
   [(f) (call/cc-via-composable f (default-continuation-prompt-tag))]
   [(f tag)
    (call-with-composable-continuation
     (lambda (k)
       (abort-current-continuation
        tag
        (lambda ()
          (k (f (lambda vs
                  (abort-current-continuation 
                   tag 
                   (lambda () 
                     (call-with-continuation-prompt
                      (lambda ()
                        (apply k vs))
                      tag
                      (lambda (thunk) (thunk))))))))))))]))
                                           
(define call-with-continuation-prompt-for-composable
  (case-lambda
   [(f) (call-with-continuation-prompt-for-composable
         f
         (default-continuation-prompt-tag))]
   [(f tag)
    (call-with-continuation-prompt f
                                   tag
                                   (lambda (thunk) (thunk)))]))

(define (thread-for-composable thunk)
  (thread (lambda ()
            (call-with-continuation-prompt-for-composable
             (lambda () (thunk))))))

(define-syntax (with-cc-variants stx)
  (syntax-case stx ()
    [(_ body)
     (with-syntax ([call/cc (datum->syntax stx 'call/cc)]
                   [let/cc (datum->syntax stx 'let/cc)]
                   [call-with-continuation-prompt
                    (datum->syntax stx 'call-with-continuation-prompt)]
                   [thread (datum->syntax stx 'thread)])
       #'(begin
           (define (a-test call/cc call-with-continuation-prompt thread)
             (define-syntax let/cc
               (syntax-rules ()
                 [(_ id bdy (... ...)) 
                  (call/cc (lambda (id) bdy (... ...)))]))
             body)
           (a-test call/cc call-with-continuation-prompt thread)
           (a-test call/cc-via-composable
                   call-with-continuation-prompt-for-composable
                   thread-for-composable)
           (a-test call/cc-via-aborted-and-restored-composable
                   call-with-continuation-prompt-for-composable
                   thread-for-composable)))]))

;; ----------------------------------------

(load-relative "prompt-tests.rktl")

;; ----------------------------------------

;; Run the whole thing in a thread with no prompts around evaluation.
;; This tests the special case of the implicit prompt at the start
;; of a thread.
(thread-wait
 (thread
  (lambda ()
    (namespace-set-variable-value! 'running-prompt-tests-in-thread? #t)
    (let ([p (open-input-file (build-path
                               (or (current-load-relative-directory)
                                   (current-directory))
                               "prompt-tests.rktl"))])
      (let loop ()
        (let ([r (read-syntax (object-name p) p)])
          (unless (eof-object? r)
            (eval r)
            (loop))))))))

;; ----------------------------------------
;; Check that a constant-space loop doesn't
;; accumulate memory (test by Nicolas Oury)

(when (custodian-memory-accounting-available?) ; as a check for 3m-ness
  (define prompt1 (make-continuation-prompt-tag 'p1))
  (define prompt2 (make-continuation-prompt-tag 'p2))

  (define (capture-and-abort prompt-tag)
    (call-with-composable-continuation
     (lambda (k) (abort-current-continuation prompt-tag k))
     prompt-tag))

  (define (go i)
    (call-with-continuation-prompt
     (lambda ()
       (call-with-continuation-prompt
        (lambda()
          (for ((j i))
            (capture-and-abort prompt1)
            (capture-and-abort prompt2)))
        prompt2))
     prompt1))

  (test (void) go 100000))

;; ----------------------------------------
;; A GC test:

(require racket/control)

(let ()
  (define (loop n)
    (shift s (if (zero? n)
                 (void)
                 (loop (sub1 n)))))
  (define (overflow-prompt-go)
    (reset (loop 50000)))
  (test (void) overflow-prompt-go))

;; ----------------------------------------
;; control proxies

(define imp-tag
  (impersonate-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x) (* x 2))
   (lambda (x) (+ x 1))))

(define imp-tag-2
  (impersonate-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x y) (values (* x 2) (* y 2)))
   (lambda (x y) (values (+ x 1) (+ y 1)))))

(define imp-tag-3
  (impersonate-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x y) (values (* x 2) (* y 2)))
   (lambda (x y) x)))

(define imp-tag-4
  (impersonate-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x y) (values x x x))
   (lambda (x y) (values x y))))

(define cha-tag
  (chaperone-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x) (if (number? x) x (error "fail")))
   (lambda (x) x)))

(define bad-tag
  (chaperone-prompt-tag
   (make-continuation-prompt-tag)
   (lambda (x) 42)
   (lambda (x) x)))

(define (do-test tag . rst)
  (call-with-continuation-prompt
    (lambda ()
      (apply abort-current-continuation
             (cons tag rst)))
    tag
    (lambda x x)))

(test '(12) do-test imp-tag 5)
(test '(12 14) do-test imp-tag-2 5 6)
(err/rt-test (do-test imp-tag-2 5) exn:fail?)
(err/rt-test (do-test imp-tag-3 10 11) exn:fail?)
(err/rt-test (do-test imp-tag-4 10 11) exn:fail?)
(test '(7) do-test cha-tag 7)
(err/rt-test (do-test cha-tag "bad") exn:fail?)
(err/rt-test (do-test bad-tag 5) exn:fail?)

;;----------------------------------------

(report-errs)
