;; Multimaps (maps from one key to multiple values),
;; implemented in terms of mappings (SRFI 146) and sets (SRFI 113)
(define-library (schemepunk multimap)
  (export multimap multimap?
          multimap->mapping multimap-key-comparator multimap-value-comparator
          multimap-copy
          multimap-ref
          multimap-adjoin multimap-adjoin! multimap-adjoin-set multimap-adjoin-set!
          multimap-delete-key multimap-delete-key! multimap-clear!
          multimap-delete-value multimap-delete-value!
          multimap-union multimap-union! multimap-difference
          multimap-contains? multimap-contains-key?
          multimap-keys
          multimap-value-sets multimap-values
          multimap-key-count multimap-value-count multimap-empty?)

  (import (scheme base)
          (schemepunk syntax)
          (schemepunk function)
          (schemepunk list)
          (schemepunk comparator)
          (schemepunk set)
          (schemepunk mapping)
          (schemepunk show span)
          (schemepunk show block)
          (schemepunk show block datum))

  (begin
    (define-record-type Multimap
      (make-multimap mapping value-comparator)
      multimap?
      (mapping multimap->mapping set-multimap-mapping!)
      (value-comparator multimap-value-comparator))

    (define (multimap key-comparator value-comparator)
      (assume (comparator? key-comparator))
      (assume (comparator? value-comparator))
      (make-multimap (mapping key-comparator) value-comparator))

    (define (multimap-key-comparator mmap)
      (mapping-key-comparator (multimap->mapping mmap)))

    (define (multimap-copy mmap)
      (assume (multimap? mmap))
      (make-multimap
        (mapping-map-values set-copy (multimap->mapping mmap))
        (multimap-value-comparator mmap)))

    (define (multimap-ref mmap key)
      (assume (multimap? mmap))
      (mapping-ref
        (multimap->mapping mmap)
        key
        (λ() (set (multimap-value-comparator mmap)))))

    (define (multimap-adjoin mmap key value)
      (assume (multimap? mmap))
      (make-multimap
        (mapping-update (multimap->mapping mmap) key
          (cut set-adjoin <> value)
          (λ() (set (multimap-value-comparator mmap))))
        (multimap-value-comparator mmap)))

    (define (multimap-adjoin! mmap key value)
      (assume (multimap? mmap))
      (set-multimap-mapping! mmap
        (mapping-update! (multimap->mapping mmap) key
          (cut set-adjoin! <> value)
          (λ() (set (multimap-value-comparator mmap)))))
      mmap)

    (define (multimap-adjoin-set mmap key vals)
      (assume (multimap? mmap))
      (assume (set? vals))
      (assume (eq? (multimap-value-comparator mmap) (set-element-comparator vals)))
      (chain (multimap->mapping mmap)
             (mapping-update _ key identity (λ() (set-copy vals)) (cut set-union <> vals))
             (make-multimap _ (multimap-value-comparator mmap))))

    (define (multimap-adjoin-set! mmap key vals)
      (assume (multimap? mmap))
      (assume (set? vals))
      (assume (eq? (multimap-value-comparator mmap) (set-element-comparator vals)))
      (set-multimap-mapping! mmap
        (chain (multimap->mapping mmap)
               (mapping-update! _ key identity (λ() (set-copy vals)) (cut set-union! <> vals))))
      mmap)

    (define (multimap-delete-key mmap key)
      (assume (multimap? mmap))
      (make-multimap
        (mapping-delete (multimap->mapping mmap) key)
        (multimap-value-comparator mmap)))

    (define (multimap-delete-key! mmap key)
      (assume (multimap? mmap))
      (set-multimap-mapping! mmap
        (mapping-delete! (multimap->mapping mmap) key))
      mmap)

    (define (multimap-delete-value mmap key value)
      (assume (multimap? mmap))
      (let1 m (multimap->mapping mmap)
        (mapping-ref m key
          (λ() mmap)
          (λ=> (set-delete _ value)
               (mapping-set m key _)
               (make-multimap _ (multimap-value-comparator mmap))))))

    (define (multimap-delete-value! mmap key value)
      (assume (multimap? mmap))
      (let1 m (multimap->mapping mmap)
        (mapping-ref m key
          (λ() mmap)
          (λ vs (chain (set-delete! vs value)
                       (mapping-set! m key _)
                       (set-multimap-mapping! mmap _))
                mmap))))

    (define (multimap-union lhs rhs)
      (assume (multimap? lhs))
      (assume (multimap? rhs))
      (assume (eq? (multimap-key-comparator lhs) (multimap-key-comparator rhs)))
      (assume (eq? (multimap-value-comparator lhs) (multimap-value-comparator rhs)))
      (mapping-fold
        (λ(k vs m) (multimap-adjoin-set m k vs))
        lhs
        (multimap->mapping rhs)))

    (define (multimap-union! lhs rhs)
      (assume (multimap? lhs))
      (assume (multimap? rhs))
      (assume (eq? (multimap-key-comparator lhs) (multimap-key-comparator rhs)))
      (assume (eq? (multimap-value-comparator lhs) (multimap-value-comparator rhs)))
      (mapping-fold
        (λ(k vs m) (multimap-adjoin-set! m k vs))
        lhs
        (multimap->mapping rhs)))

    (define (multimap-difference lhs rhs)
      (assume (multimap? lhs))
      (assume (multimap? rhs))
      (make-multimap
        (mapping-fold
          (λ(k vs m)
            (let1 new-set (set-difference vs (multimap-ref rhs k))
              (if (set-empty? new-set) m (mapping-set! m k new-set))))
          (mapping (multimap-key-comparator lhs))
          (multimap->mapping lhs))
        (multimap-value-comparator lhs)))

    (define (multimap-contains-key? mmap key)
      (assume (multimap? mmap))
      (mapping-contains? (multimap->mapping mmap) key))

    (define (multimap-contains? mmap key value)
      (assume (multimap? mmap))
      (set-contains? (multimap-ref mmap key) value))

    (define (multimap-keys mmap)
      (assume (multimap? mmap))
      (mapping-keys (multimap->mapping mmap)))

    (define (multimap-value-sets mmap)
      (assume (multimap? mmap))
      (mapping-values (multimap->mapping mmap)))

    (define (multimap-values mmap)
      (assume (multimap? mmap))
      (fold (λ(x y) (set-union! y x))
            (set (multimap-value-comparator mmap))
            (multimap-value-sets mmap)))

    (define (multimap-key-count mmap)
      (assume (multimap? mmap))
      (mapping-size (multimap->mapping mmap)))

    (define (multimap-value-count mmap)
      (assume (multimap? mmap))
      (chain (multimap-value-sets mmap)
             (map set-size _)
             (fold + 0 _)))

    (define (multimap-empty? mmap)
      (assume (multimap? mmap))
      (mapping-empty? (multimap->mapping mmap)))

    (define (multimap-clear! mmap)
      (assume (multimap? mmap))
      (set-multimap-mapping! mmap (mapping (multimap-key-comparator mmap))))

    (define (multimap->block mmap)
      (define color (datum-color-record))
      (if (multimap-empty? mmap)
        (make-block (list (text-span "#,(multimap)" color)))
        (make-block
          (list
            (text-span "#,(multimap" color)
            (whitespace-span))
          (intercalate (whitespace-span)
            (map
              (λ((k . v))
                (make-block
                  (list
                    (text-span "(" color)
                    (datum->block k)
                    (whitespace-span))
                  (chain (set->list v)
                         (map datum->block _)
                         (intercalate (whitespace-span) _))
                  (list
                    (text-span ")" color))))
              (mapping->alist (multimap->mapping mmap))))
          (list
            (text-span ")" color)))))

    (register-datum-writer! multimap? multimap->block)))
