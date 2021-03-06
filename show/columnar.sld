(define-library (schemepunk show columnar)
  (export columnar tabular
          boxed boxed/double boxed/ascii boxed/custom
          wrapped wrapped/list wrapped/char justified
          collapsed-if-one-line
          from-file line-numbers)

  (import (scheme base)
          (scheme file)
          (schemepunk syntax)
          (schemepunk function)
          (schemepunk list)
          (schemepunk generator)
          (schemepunk show base)
          (schemepunk show span)
          (schemepunk show block))

  (begin
    (define (span-list-width string-width spans)
      (fold + 0 (map (compose string-width span-text) spans)))

    (define (pad-span size pad-char)
      (whitespace-span (make-string size pad-char)))

    (define (take-line gen string-width)
      (let loop ((span (gen)) (spans '()))
        (cond
          ((eof-object? span)
            (and (pair? spans) (reverse spans)))
          ((eqv? 'newline (span-type span))
            (reverse spans))
          (else
            (loop (gen) (cons span spans))))))

    (define (pad-column-line spans align used-width width pad-char)
      (case (and (< used-width width) align)
        ((left)
          (snoc spans (pad-span (- width used-width) pad-char)))
        ((right)
          (cons (pad-span (- width used-width) pad-char) spans))
        ((center)
          (let* ((pad (- width used-width))
                 (half-pad (quotient pad 2)))
            `(,(pad-span half-pad pad-char)
              ,@spans
              ,(pad-span (- pad half-pad) pad-char))))
        (else spans)))

    (define (column-gen string-width pad-char columns)
      (define (next-gen)
        (match
          (fold-right
            (λ((gen width align infinite?) (accum continue?))
              (match (take-line gen string-width)
                (#f
                  (list (if align (cons (pad-span width pad-char) accum)
                                  accum)
                        continue?))
                (spans
                  (list
                    (append (pad-column-line spans
                                             align
                                             (span-list-width string-width spans)
                                             width
                                             pad-char)
                            accum)
                    (or continue? (not infinite?))))))
            `((,(newline-span)) #f)
            columns)
          ((line-gen valid?)
            (if valid? (list->generator line-gen) (generator)))))
      (define gen (next-gen))
      (λ()
        (let1 span (gen)
          (if (eof-object? span)
            (begin (set! gen (next-gen)) (gen))
            span))))

    (define (table-gen string-width pad-char columns)
      (let loop ((rows '())
                 (widths (map (λ((_ w . _)) (if (integer? w) w 0)) columns)))
        (match
          (fold-right
            (λ(old-width (gen _ align infinite?) (row widths continue?))
              (match (take-line gen string-width)
                (#f
                  (list (cons '() row) (cons old-width widths) continue?))
                (spans
                  (list (cons spans row)
                        (cons (max old-width (span-list-width string-width spans))
                              widths)
                        (or continue? (not infinite?))))))
            '(() () #f)
            widths
            columns)
          ((_ widths #f)
            (fold
              (λ(cells gen)
                (chain (append-map
                         (λ(width (_ _ align _) spans)
                           (chain (span-list-width string-width spans)
                                  (pad-column-line spans align _ width pad-char)))
                         widths
                         columns
                         cells)
                       (list->generator _)
                       (gappend _ (generator (newline-span)) gen)))
              (generator)
              rows))
          ((row widths #t)
            (loop (cons row rows) widths)))))

    (define (build-columns column-args string-width pad-char)
      (match-let1 (columns . _)
        (fold
          (λ(arg (cols width align infinite))
            (match arg
              ((or 'left 'right 'center)
                (list cols width arg infinite))
              ('infinite
                (list cols width align #t))
              ((? number?)
                (assume (positive? arg))
                (assume (or (integer? arg) (is 0 < arg < 1)))
                (list cols arg align infinite))
              ((? string?)
                `(((,(each-in-list (circular-list arg nl)) ,(string-width arg) #f #t)
                   ,@cols)
                  ,width
                  ,align
                  ,infinite))
              ((? procedure?)
                `(((,arg ,width ,align ,infinite) ,@cols) #f left #f))))
          '(() #f left #f)
          column-args)
        ;; Remove unnecessary space padding on the right side.
        ;; SRFI 166 doesn't specify this, but Chibi does it, so we will too.
        (when (and (pair? columns)
                   (eqv? #\space pad-char)
                   (eqv? 'left (caddar columns)))
          (set-car! (cddar columns) #f))
        columns))

    (define (distribute-column-widths total-width columns)
      (match-let*
        ((split-among
           (count (λ((_ width . _))
                    (when (integer? width)
                      (set! total-width (- total-width width)))
                    (not width))
                  columns))
         ((columns total-width)
           (fold (λ((gen width . rest) (columns remaining-width))
                   (if (and (number? width) (< 0 width 1))
                     (let1 exact-width (round (* total-width width))
                       `(((,gen ,exact-width ,@rest) ,@columns)
                         ,(- remaining-width exact-width)))
                     `(((,gen ,width ,@rest) ,@columns)
                       ,remaining-width)))
                 `(() ,total-width)
                 columns))
         (split-width
           (if (zero? split-among) 0 (max 0 (quotient total-width split-among))))
         (leftover
           (- total-width (* split-among split-width))))
        (map (λ((gen width . rest))
               `(,gen
                 ,(or width
                      (if (> leftover 0)
                        (begin (set! leftover (- leftover 1))
                               (+ split-width 1))
                        split-width))
                 ,@rest))
             columns)))

    (define (columnar . columns)
      (fn ((total-width width) string-width pad-char (start-row row))
        (λ vars
          ((span-generator->formatter
             (chain (build-columns columns string-width pad-char)
                    (distribute-column-widths total-width _)
                    (map
                      (λ((fmt col-width . rest))
                        `(,((with ((row start-row)
                                   (col 0)
                                   (width col-width)
                                   (break-into-spans? #t))
                               fmt)
                             vars)
                          ,col-width
                          ,@rest))
                      _)
                    (column-gen string-width pad-char _)))
           vars))))

    (define (tabular . columns)
      (fn ((total-width width) string-width pad-char (start-row row))
        (λ vars
          ((span-generator->formatter
             (let1 cols (build-columns columns string-width pad-char)
               (chain (distribute-column-widths total-width cols)
                      (map
                        (λ((_ orig-width . _) (fmt col-width . rest))
                          `(,((with ((row start-row)
                                     (col 0)
                                     (width col-width)
                                     (break-into-spans? #t))
                                fmt)
                              vars)
                            ,(if orig-width col-width 0)
                            ,@rest))
                        cols
                        _)
                      (table-gen string-width pad-char _))))
           vars))))

    (define (boxed . contents)
      (apply boxed/custom each #\─ #\│ #\┌ #\┐ #\└ #\┘ contents))

    (define (boxed/double . contents)
      (apply boxed/custom each #\═ #\║ #\╔ #\╗ #\╚ #\╝ contents))

    (define (boxed/ascii . contents)
      (apply boxed/custom each #\- #\| #\+ #\+ #\+ #\+ contents))

    (define (boxed/custom color h v nw ne sw se . contents)
      (call-with-output-generator
        (tabular
          1 'infinite (each-in-list (circular-list (color v) nl))
          (each-in-list contents)
          1 'infinite (each-in-list (circular-list (color v) nl)))
        (λ gen
          (fn (string-width)
            (let*-values
              (((gen gen2) (gfork gen))
               ((len) (chain gen2
                             (gtake-while (compose (isnt _ eq? 'newline) span-type) _)
                             (gmap (compose string-width span-text) _)
                             (generator-fold + 0 _))))
              (each
                (color nw (make-string (- len 2) h) ne)
                nl
                (span-generator->formatter gen)
                fl
                (color sw (make-string (- len 2) h) se)
                nl))))))

    (define (from-file pathname)
      (let1 port (open-input-file pathname)
        (span-generator->formatter
          (char-generator->span-generator (cut read-char port)))))

    (define+ (line-numbers :optional (start 0))
      (span-generator->formatter
        (let ((n (- start 1)) (nl? #t))
          (λ() (set! nl? (not nl?))
               (if nl? (newline-span)
                       (begin (set! n (+ n 1))
                              (text-span (number->string n))))))))

    ;; `seq' is a list or vector of pre-tokenized words. `line' is called
    ;; on each wrapped line and the accumulator, starting with `knil'.
    ;; The optional `last-line' is used instead on the last line of the
    ;; paragraph.
    (define+ (wrap-fold-words seq knil max-width get-width line :optional (last-line line))
      (let* ((vec (if (list? seq) (list->vector seq) seq))
             (len (vector-length vec))
             (len-1 (- len 1))
             (breaks (make-vector len #f))
             (penalties (make-vector len #f))
             (widths (vector-map get-width vec)))
        (define (largest-fit i)
          (let lp ((j (+ i 1)) (width (vector-ref widths i)))
            (let1 width (+ width 1 (vector-ref widths j))
              (cond
                ((>= width max-width) (- j 1))
                ((>= j len-1) len-1)
                (else (lp (+ j 1) width))))))
        (define (min-penalty! i)
          (cond
            ((>= i len-1) 0)
            ((vector-ref penalties i))
            (else
             (vector-set! penalties i (expt (+ max-width 1) 3))
             (vector-set! breaks i i)
             (let1 k (largest-fit i)
               (let lp ((j i) (width 0))
                 (when (<= j k)
                   (let* ((width (+ width (vector-ref widths j)))
                          (break-penalty
                            (+ (max 0 (expt (- max-width (+ width (- j i))) 3))
                               (min-penalty! (+ j 1)))))
                     (when (< break-penalty (vector-ref penalties i))
                       (vector-set! breaks i j)
                       (vector-set! penalties i break-penalty))
                     (lp (+ j 1) width)))))
             (when (>= (vector-ref breaks i) len-1)
               (vector-set! penalties i 0))
             (vector-ref penalties i))))
        (define (sub-list i j)
          (let lp ((i i) (res '()))
            (if (> i j)
              (reverse res)
              (lp (+ i 1) (cons (vector-ref vec i) res)))))
        (cond
         ((zero? len)
           ;; degenerate case
           (last-line '() knil))
         (else
           ;; compute optimum breaks
           (vector-set! breaks len-1 len-1)
           (vector-set! penalties len-1 0)
           (min-penalty! 0)
           ;; fold
           (let lp ((i 0) (acc knil))
             (let1 break (vector-ref breaks i)
               (if (>= break len-1)
                 (last-line (sub-list i len-1) acc)
                 (lp (+ break 1) (line (sub-list i break) acc)))))))))

    (define (wrapped . ls)
      (fn (width string-width pad-char)
        (call-with-output-generator
          (with ((break-into-spans? #t)) (each-in-list ls))
          (λ=> (generator-fold
                 (λ(span (word . words))
                   (case (span-type span)
                     ((whitespace newline)
                       (if (null? word) `(() ,@words) `(() ,word ,@words)))
                     (else
                       `((,@word ,span) ,@words))))
                 '(())
                 _)
               (filter pair? _)
               (reverse _)
               (wrap-fold-words _
                                '()
                                width
                                (cut span-list-width string-width <>)
                                cons)
               (reverse _)
               (joined
                 (λ=> (map (λ=> (list->generator _) (span-generator->formatter _)) _)
                      (joined each _ pad-char))
                 _
                 fl)))))

    (define (wrapped/list ls)
      (fn (width string-width pad-char)
        (joined
          (cut joined displayed <> pad-char)
          (reverse (wrap-fold-words ls '() width string-width cons))
          fl)))

    (define (wrapped/char . ls)
      (fn (width string-width substring/width)
        (call-with-output-generator (each-in-list ls) (λ gen
          (span-generator->formatter
            (let1 remaining width
              (λ()
                (let* ((span (gen))
                       (w (and (span? span) (string-width (span-text span)))))
                  (cond
                    ((eof-object? span) span)
                    ((eqv? 'newline (span-type span))
                      (set! remaining width)
                      span)
                    ((<= w remaining)
                      (set! remaining (- remaining w))
                      span)
                    ((zero? remaining)
                      (set! remaining width)
                      (set! gen (gappend (generator span) gen))
                      (newline-span))
                    (else
                      (let1 split-at remaining
                        (set! gen (gappend (generator
                                             (newline-span)
                                             (span-map-text (cut substring/width <> split-at) span))
                                           gen))
                        (set! remaining (- w split-at))
                        (span-map-text (cut substring/width <> 0 split-at) span))))))))))))

    (define (justified . ls)
      (fn (width string-width pad-char)
        (call-with-output-generator
          (with ((break-into-spans? #t)) (each-in-list ls))
          (λ=> (generator-fold
                 (λ(span (word . words))
                   (case (span-type span)
                     ((whitespace newline)
                       (if (null? word) `(() ,@words) `(() ,word ,@words)))
                     (else
                       `((,@word ,span) ,@words))))
                 '(())
                 _)
               (filter pair? _)
               (reverse _)
               (wrap-fold-words _
                                '()
                                width
                                (cut span-list-width string-width <>)
                                cons)
               (match _
                 (() fl)
                 ((last . init)
                   (each
                     (joined
                       (λ words
                         (let1 lengths (map (cut span-list-width string-width <>) words)
                           (chain (reverse words)
                             (map (λ(len spans) (list (list->generator spans) len #f #f)) lengths _)
                             (intercalate `(,(generator) #f left #f) _)
                             (distribute-column-widths width _)
                             (column-gen string-width pad-char _)
                             (span-generator->formatter _))))
                       (reverse init))
                     (joined (λ=> (list->generator _) (span-generator->formatter _))
                             last
                             pad-char))))))))

    (define (collapsed-if-one-line . ls)
      (call-with-output-generator (wrapped (each-in-list ls))
        (λ gen
          (if (eof-object? ((gfilter (compose (is _ eqv? 'newline) span-type) gen)))
            (wrapped (each-in-list ls))
            (each-in-list ls)))))))
