#lang scheme
(require web-server/servlet
         web-server/servlet-env
         (for-syntax scheme)
         (for-syntax syntax/kerncase))

(provide 
 (all-from-out web-server/servlet)
 (except-out (all-from-out scheme) #%module-begin)
 (rename-out [web-module-begin #%module-begin]))

(define extra-files-path #f)
(define launch-browser? #t)

(provide/contract
 (static-files-path ((or/c string? path?) . -> . void?)))
(define (static-files-path path)
  (set! extra-files-path 
        (if (path? path) 
            path
            (string->path path))))

(provide no-web-browser)
(define (no-web-browser)
  (set! launch-browser? false))

;; check-for-def : syntax syntax-list -> void
;; Expands body-stxs and determines if id-stx is bound therein.
;; If not error w/ error-msg. stx is the root syntax context for everything
(define-for-syntax (check-for-def stx id-stx error-msg body-stxs)
  (with-syntax ([(pmb body ...)
                 (local-expand 
                  (quasisyntax/loc stx
                    (#%module-begin #,@body-stxs))
                  'module-begin 
                  empty)])
    (let loop ([syns (syntax->list #'(body ...))])
      (if (empty? syns)
          (raise-syntax-error 'insta error-msg stx)
          (kernel-syntax-case (first syns) #t
            [(define-values (id ...) expr)
             (unless
                 (ormap (lambda (id)
                          (and (identifier? id)
                               (free-identifier=? id id-stx)))
                        (syntax->list #'(id ...)))
               (loop (rest syns)))
             ]
            [_
             (loop (rest syns))])))
    (quasisyntax/loc stx
      (pmb body ...))))

(define-syntax (web-module-begin stx)
  (syntax-case stx ()
    [(_ body ...)
     (let* ([start (datum->syntax stx 'start)]
            [expanded (check-for-def stx 
                                     start "You must provide a 'start' request handler."
                                     #'(body ...))])
       (quasisyntax/loc stx
         (#,@expanded
          (provide/contract (#,start (request? . -> . response?)))
          (if extra-files-path
              (serve/servlet #,start
                             #:extra-files-path extra-files-path
                             #:launch-browser? launch-browser?)
              (serve/servlet #,start
                             #:launch-browser? launch-browser?)))))]))