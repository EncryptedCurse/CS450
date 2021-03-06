; #lang r5rs

;;; Fast modular exponentiation. From textbook section 1.2.4.
(define (expmod b e m)
	(cond
		((zero? e) 1)
		(
			(even? e)
			(remainder
				(square (expmod b (/ e 2) m))
				m
			)
		)
		(else
			(remainder
				(* b (expmod b (- e 1) m))
				m
			)
		)
	)
)

(define (square x) (* x x))


;;; An RSA key consists of a modulus and an exponent.
(define make-key cons)
(define key-modulus car)
(define key-exponent cdr)

(define (RSA-transform number key)
	(expmod
		number
		(key-exponent key)
		(key-modulus key)
	)
)


;;; Compresses a list of numbers to a single number for use in creating digital signatures.
(define (compress intlist)
	(define (add-loop l)
		(if (null? l)
			0
			(+ (car l) (add-loop (cdr l)))
		)
	)
	(modulo (add-loop intlist) (expt 2 28))
)


;;; To choose a prime, we start searching at a random odd number in a specifed range.
(#%require (only racket/base random))

(define (choose-prime smallest range)
	(let
		((start (+ smallest (choose-random range))))
		(search-for-prime (if (even? start) (+ start 1) start))
	)
)

(define (search-for-prime guess)
	(if (fast-prime? guess 2)
		guess
		(search-for-prime (+ guess 2))
	)
)


;;; Picks a random number in a given range but makes sure that the specified range is not too big for Scheme's RANDOM primitive.
(define choose-random
	(let
		((max-random-number (expt 10 18)))
		(lambda (n)
			(random (inexact->exact(floor (min n max-random-number))))
		)
	)
)


;;; The Fermat test for primality. From texbook section 1.2.6.
(define (fermat-test n)
	(let
		((a (choose-random n)))
		(= (expmod a n n) a)
	)
)

(define (fast-prime? n times)
	(cond
		((zero? times) #t)
		((fermat-test n) (fast-prime? n (- times 1)))
		(else #f)
	)
)


;;; RSA key pairs are pairs of keys.
(define make-key-pair cons)
(define key-pair-public car)
(define key-pair-private cdr)

;;; Generate an RSA key pair (k1, k2). This has the property that transforming
;;; by k1 and transforming by k2 are inverse operations. Thus, we can use one
;;; key as the public key andone as the private key.
(define (generate-RSA-key-pair)
	(let ((size (expt 2 14)))
		; We choose p and q in the range from 2^14 to 2^15. This insures that the
		; pq will be in the range 2^28 to 2^30, which is large enough to encode
		; four characters per number.
		(let
			(
				(p (choose-prime size size))
				(q (choose-prime size size))
			)
			(if (= p q) ; check that we haven't chosen the same prime twice (VERY unlikely)
				(generate-RSA-key-pair)
				(let ((n (* p q))
					(m (* (- p 1) (- q 1))))
					(let ((e (select-exponent m)))
						(let ((d (invert-modulo e m)))
							(make-key-pair (make-key n e) (make-key n d)))
						)
				)
			)
		)
	)
)


;;; The RSA exponent can be any random number relatively prime to m.
(define (select-exponent m)
	(let
		((try (choose-random m)))
		(if (= (gcd try m) 1)
			try
			(select-exponent m)
		)
	)
)


;;; Solve ax + by = 1. The idea is to let a = bq + r and solve bx + ry = 1 recursively.
(define (solve-ax+by=1 a b)
	(let
		(
			(q (quotient a b))
			(r (remainder a b))
		)
		(if (= r 0)
			(cons 0 (/ 1 b))
			(let*
				(
					(sol (solve-ax+by=1 b r))
					(x (car sol))
					(y (cdr sol))
				)
				(cons y (- x (* q y)))
			)
		)
	)
)


;;; Invert e modulo m.
(define (invert-modulo e m)
	(if (= (gcd e m) 1)
		(let
			((y (cdr (solve-ax+by=1 m e))))
			(modulo y m) ; just in case y was negative
		)
		(display "error!")
	)
)


;;; Actual RSA encryption and decryption.
(define (RSA-encrypt string key1)
	(RSA-convert-list (string->intlist string) key1))

(define (RSA-convert-list intlist key)
	(let ((n (key-modulus key)))
		(define (convert l sum)
			(if (null? l)
				'()
				(let
					((x (RSA-transform (modulo (- (car l) sum) n) key)))
					(cons x (convert (cdr l) x)))
			)
		)
		(convert intlist 0)
	)
)

(define (RSA-decrypt intlist key2)
	(intlist->string (RSA-unconvert-list intlist key2)))

(define (RSA-unconvert-list intlist key)
	(let
		((n (key-modulus key)))
		(define (convert l sum)
			(if (null? l)
				'()
				(let
					((x (modulo (+ (RSA-transform (car l) key) sum) n)))
					(cons x (convert (cdr l) (car l)))
				)
		   )
		)
		(convert intlist 0)
	)
)


;;; Searching for divisors.

;;; The following procedure is very much like the find-divisor procedure of
;;; section 1.2.6 of the text, except that it increments the test divisor by
;;; 2 each time (compare exercise 1.18). You should be careful to call it
;;; only with odd numbers n.
(define (smallest-divisor n)
	(find-divisor n 3))

(define (find-divisor n test-divisor)
	(cond
		((> (square test-divisor) n) n)
		((divides? test-divisor n) test-divisor)
		(else (find-divisor n (+ test-divisor 2)))
	)
)

(define (divides? a b)
	(= (remainder b a) 0))


;;; The following procedures are used to convert between strings, and lists of
;;; integers in the range 0 through 2^28.

;;; Convert a string into a list of integers, where each integer encodes a block
;;; of characters. Pad the string with spaces if the length of the string is not
;;; a multiple of the blocksize.
(define (string->intlist string)
	(let ((blocksize 4))
		(let ((padded-string (pad-string string blocksize)))
			(let ((length (string-length padded-string)))
				(block-convert padded-string 0 length blocksize)))))

(define (block-convert string start-index end-index blocksize)
	(if (= start-index end-index)
		'()
		(let ((block-end (+ start-index blocksize)))
			(cons (charlist->integer
			   (string->list (substring string start-index block-end)))
					(block-convert string block-end end-index blocksize)))))

(define (pad-string string blocksize)
	(let ((rem (remainder (string-length string) blocksize)))
		(if (= rem 0)
			string
			(string-append string (make-string (- blocksize rem) #\Space)))))

;;; Encode a list of characters as a single number. Each character gets converted to an
;;; ASCII code between 0 and 127. Then the resulting number is c[0]+c[1]*128+c[2]*128^2,...
(define (charlist->integer charlist)
	(let ((n (char->integer (car charlist))))
		(if (null? (cdr charlist))
			n
			(+ n (* 128 (charlist->integer (cdr charlist)))))))

;;; Convert a list of integers to a string.
;;; (Inverse of string->intlist, except for the padding.)
(define (intlist->string intlist)
	(list->string
		(apply
			append
			(map integer->charlist intlist)
		)
	)
)

;;; Decode an integer into a list of characters.
;;; (This is essentially writing the integer in base 128, and converting each "digit" to a character.)
(define (integer->charlist integer)
	(if (< integer 128)
		(list (integer->char integer))
		(cons
			(integer->char (remainder integer 128))
			(integer->charlist (quotient integer 128))
		)
	)
)


;;; The following procedure is handy for timing things.
(#%require (only racket/base current-milliseconds))
(define (runtime) (current-milliseconds))
(define (timed f . args)
	(let
		((init (runtime)))
		(let
			((v (apply f args)))
			(display (list 'time: (- (runtime) init)))
			(newline)
			v
		)
	)
)


(define signed-message cons)
(define message car)
(define signature cdr)

(define (encrypt-and-sign unsigned-msg priv pub)
	(let*
		(
			(encrypted-msg (RSA-encrypt unsigned-msg pub))
			(unencrypted-sig (compress encrypted-msg))
			(encrypted-sig (RSA-transform unencrypted-sig priv))
		)
		(signed-message encrypted-msg encrypted-sig)
	)
)

(define (authenticate-and-decrypt signed-msg pub priv)
	(let
		(
			(decrypted-msg (RSA-decrypt (message signed-msg) priv))
			(expected-sig (compress (message signed-msg)))
			(real-sig (RSA-transform (signature signed-msg) pub))
		)
		(if (= real-sig expected-sig)
			decrypted-msg
			#f
		)
	)
)


;;; Find private key given public key.
(define (crack-rsa pub)
	(let*
		(
			(n (key-modulus pub))
			(e (key-exponent pub))
			(p (smallest-divisor n))
			(q (/ n p))
			(m (* (- p 1) (- q 1)))
		)
		(make-key n (invert-modulo e m))
	)
)


;;; Some initial test data.
(define test-key-pair1
	(make-key-pair
		(make-key 816898139 180798509)
		(make-key 816898139 301956869)
	)
)

(define test-key-pair2
	(make-key-pair
		(make-key 513756253 416427023)
		(make-key 513756253 462557987)
	)
)


;;; Public keys for political figures.
(define donald-trump-public-key (make-key 833653283 583595407))
(define mike-pence-public-key (make-key 655587853 463279441))
(define nancy-pelosi-public-key (make-key 507803083 445001911))
(define aoc-public-key (make-key 865784123 362279729))
(define michael-cohen-public-key (make-key 725123713 150990017))
(define ivanka-trump-public-key (make-key 376496027 270523157))
(define bernie-sanders-public-key (make-key 780450379 512015071))
(define kamala-harris-public-key (make-key 412581307 251545759))
(define joe-biden-public-key (make-key 718616329 290820109))
(define joe-biden-private-key (make-key 718616329 129033029))

;;; Cracked private keys for political figures.
(define donald-trump-private-key (crack-rsa donald-trump-public-key))
(define mike-pence-private-key (crack-rsa mike-pence-public-key))
(define nancy-pelosi-private-key (crack-rsa nancy-pelosi-public-key))
(define aoc-private-key (crack-rsa aoc-public-key))
(define michael-cohen-private-key (crack-rsa michael-cohen-public-key))
(define ivanka-trump-private-key (crack-rsa ivanka-trump-public-key))
(define bernie-sanders-private-key (crack-rsa bernie-sanders-public-key))
(define kamala-harris-private-key (crack-rsa kamala-harris-public-key))