;; KeyOrbit Social Impact Blockchain Smart Contract

;; Error Constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_SCORE (err u101))
(define-constant ERR_INSUFFICIENT_STAKE (err u102))
(define-constant ERR_ACCESS_DENIED (err u103))
(define-constant ERR_FRAUD_DETECTED (err u104))
(define-constant ERR_INVALID_DATA (err u105))
(define-constant ERR_NOT_FOUND (err u106))
(define-constant ERR_INSUFFICIENT_TOKENS (err u107))

;; Contract Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-active bool false)
(define-data-var base-rate uint u100)
(define-data-var fraud-threshold uint u75)
(define-data-var min-stake uint u1000)

;; User Profiles
(define-map user-profiles principal {
    impact-score: uint,
    tokens: uint,
    credits: uint,
    fraud-flags: uint,
    last-activity: uint
})

;; Validators
(define-map validators principal {
    stake: uint,
    accuracy: uint,
    active: bool
})

;; Orbit Access
(define-map orbit-access principal {
    water: bool,
    education: bool,
    health: bool,
    community: bool
})

;; Marketplace Offers
(define-map offers principal {
    credits: uint,
    price: uint,
    expires: uint
})

;; Helper Functions
(define-private (get-time) block-height)

(define-private (calculate-discount (score uint))
    (if (>= score u90) u20
        (if (>= score u70) u10 u0)))

(define-private (update-access (user principal) (orbit (string-ascii 10)))
    (let ((access (default-to {water: false, education: false, health: false, community: false}
                             (map-get? orbit-access user))))
        (if (is-eq orbit "water")
            (map-set orbit-access user (merge access {water: true}))
            (if (is-eq orbit "education")
                (map-set orbit-access user (merge access {education: true}))
                (if (is-eq orbit "health")
                    (map-set orbit-access user (merge access {health: true}))
                    (map-set orbit-access user (merge access {community: true})))))
        true))

;; Admin Functions
(define-public (set-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)))

(define-public (toggle-emergency)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set emergency-active (not (var-get emergency-active)))
        (ok true)))

;; Core Functions
(define-public (register-profile (impact-score uint))
    (begin
        (asserts! (and (>= impact-score u1) (<= impact-score u100)) ERR_INVALID_SCORE)
        (map-set user-profiles tx-sender {
            impact-score: impact-score,
            tokens: u100,
            credits: u0,
            fraud-flags: u0,
            last-activity: (get-time)
        })
        (ok true)))

(define-public (verify-access (orbit (string-ascii 10)))
    (let ((profile (unwrap! (map-get? user-profiles tx-sender) ERR_ACCESS_DENIED)))
        (asserts! (>= (get impact-score profile) u50) ERR_INVALID_SCORE)
        (asserts! (< (get fraud-flags profile) u3) ERR_FRAUD_DETECTED)
        (ok (update-access tx-sender orbit))))

(define-public (stake-validator (amount uint))
    (begin
        (asserts! (>= amount (var-get min-stake)) ERR_INSUFFICIENT_STAKE)
        (map-set validators tx-sender {
            stake: amount,
            accuracy: u100,
            active: true
        })
        (ok true)))

(define-public (flag-fraud (user principal))
    (let ((validator (unwrap! (map-get? validators tx-sender) ERR_NOT_FOUND))
          (profile (unwrap! (map-get? user-profiles user) ERR_NOT_FOUND)))
        (asserts! (get active validator) ERR_UNAUTHORIZED)
        (map-set user-profiles user 
            (merge profile {fraud-flags: (+ (get fraud-flags profile) u1)}))
        (ok true)))

(define-public (trade-credits (credits uint) (price uint) (buyer principal))
    (let ((seller (unwrap! (map-get? user-profiles tx-sender) ERR_ACCESS_DENIED))
          (buyer-profile (unwrap! (map-get? user-profiles buyer) ERR_ACCESS_DENIED)))
        (asserts! (>= (get credits seller) credits) ERR_INSUFFICIENT_TOKENS)
        (asserts! (>= (get tokens buyer-profile) price) ERR_INSUFFICIENT_TOKENS)
        
        ;; Update balances
        (map-set user-profiles tx-sender 
            (merge seller {
                credits: (- (get credits seller) credits),
                tokens: (+ (get tokens seller) price)
            }))
        (map-set user-profiles buyer 
            (merge buyer-profile {
                credits: (+ (get credits buyer-profile) credits),
                tokens: (- (get tokens buyer-profile) price)
            }))
        (ok true)))

(define-public (create-offer (credits uint) (price uint) (hours uint))
    (let ((profile (unwrap! (map-get? user-profiles tx-sender) ERR_ACCESS_DENIED)))
        (asserts! (>= (get credits profile) credits) ERR_INSUFFICIENT_TOKENS)
        (asserts! (> price u0) ERR_INVALID_DATA)
        (map-set offers tx-sender {
            credits: credits,
            price: price,
            expires: (+ (get-time) (* hours u144))
        })
        (ok true)))

(define-public (negotiate-rate)
    (let ((profile (unwrap! (map-get? user-profiles tx-sender) ERR_ACCESS_DENIED))
          (score (get impact-score profile))
          (discount (calculate-discount score)))
        (asserts! (>= score u60) ERR_INVALID_SCORE)
        (ok (- (var-get base-rate) discount))))

;; Read-Only Functions
(define-read-only (get-profile (user principal))
    (map-get? user-profiles user))

(define-read-only (get-access (user principal))
    (map-get? orbit-access user))

(define-read-only (get-validator (user principal))
    (map-get? validators user))

(define-read-only (get-offer (user principal))
    (map-get? offers user))

(define-read-only (get-stats)
    {base-rate: (var-get base-rate),
     emergency: (var-get emergency-active),
     owner: (var-get contract-owner)})

;; Initialize
(var-set contract-owner tx-sender)