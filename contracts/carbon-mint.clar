;; carbon-mint.clar
;; Carbon Credit Marketplace Smart Contract

;; This contract manages the entire lifecycle of carbon credits on the Stacks blockchain
;; from issuance by verified projects to trading in the marketplace to retirement (usage)
;; for offsetting carbon footprints. It ensures transparency, prevents double-counting,
;; and maintains an immutable record of all carbon credit activities.

;; =========================================
;; Constants and Error Codes
;; =========================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ISSUER-ALREADY-EXISTS (err u101))
(define-constant ERR-ISSUER-NOT-FOUND (err u102))
(define-constant ERR-VERIFIER-ALREADY-EXISTS (err u103))
(define-constant ERR-VERIFIER-NOT-FOUND (err u104))
(define-constant ERR-CREDIT-NOT-FOUND (err u105))
(define-constant ERR-CREDIT-ALREADY-EXISTS (err u106))
(define-constant ERR-CREDIT-ALREADY-RETIRED (err u107))
(define-constant ERR-INSUFFICIENT-FUNDS (err u108))
(define-constant ERR-LISTING-NOT-FOUND (err u109))
(define-constant ERR-NOT-CREDIT-OWNER (err u110))
(define-constant ERR-INVALID-AMOUNT (err u111))
(define-constant ERR-CREDIT-NOT-VERIFIED (err u112))
(define-constant ERR-PLATFORM-PERCENTAGE-INVALID (err u113))

;; Platform settings
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PRECISION u1000000) ;; 6 decimal places for percentage calculations

;; =========================================
;; Data Maps and Variables
;; =========================================

;; Track contract administrators
(define-map administrators principal bool)

;; Track platform fee percentage (stored with PRECISION multiplier)
(define-data-var platform-fee-percentage uint u30000) ;; 3% default (0.03 * PRECISION)

;; Track platform treasury
(define-data-var platform-treasury principal CONTRACT-OWNER)

;; Authorized carbon credit issuers
(define-map issuers
  principal
  {
    name: (string-ascii 100),
    is-active: bool,
    total-issued: uint,
    registration-time: uint
  }
)

;; Authorized verification bodies
(define-map verifiers
  principal
  {
    name: (string-ascii 100),
    is-active: bool,
    standards: (list 10 (string-ascii 50)), ;; Supported verification standards (Gold Standard, Verra, etc.)
    registration-time: uint
  }
)

;; Carbon credit registry
(define-map carbon-credits
  uint ;; credit-id
  {
    issuer: principal,
    verifier: (optional principal),
    vintage-year: uint, ;; Year the offset occurred
    project-type: (string-ascii 50), ;; e.g., "Reforestation", "Solar"
    location: (string-ascii 50), ;; Country/region
    standard: (string-ascii 50), ;; Verification standard
    total-supply: uint, ;; Total tokens issued for this credit
    is-verified: bool,
    is-active: bool,
    creation-time: uint
  }
)

;; Track credit ownership
(define-map credit-balances
  {credit-id: uint, owner: principal}
  uint ;; balance
)

;; Track retired (used) credits
(define-map retired-credits
  {credit-id: uint, owner: principal}
  {
    amount: uint,
    retirement-time: uint,
    retirement-purpose: (string-ascii 100) ;; Why the credit was retired
  }
)

;; Marketplace listings
(define-map marketplace-listings
  uint ;; listing-id
  {
    seller: principal,
    credit-id: uint,
    amount: uint,
    price-per-unit: uint, ;; in microSTX
    is-active: bool,
    listing-time: uint
  }
)

;; Counter for credit IDs
(define-data-var next-credit-id uint u1)

;; Counter for listing IDs
(define-data-var next-listing-id uint u1)

;; =========================================
;; Private Functions
;; =========================================

;; Check if caller is the contract owner or an administrator
(define-private (is-authorized)
  (or (is-eq tx-sender CONTRACT-OWNER)
      (default-to false (map-get? administrators tx-sender))))

;; Check if address is an active issuer
(define-private (is-active-issuer (address principal))
  (match (map-get? issuers address)
    issuer-data (get is-active issuer-data)
    false))

;; Check if address is an active verifier
(define-private (is-active-verifier (address principal))
  (match (map-get? verifiers address)
    verifier-data (get is-active verifier-data)
    false))

;; Check if credit exists
(define-private (credit-exists (credit-id uint))
  (is-some (map-get? carbon-credits credit-id)))

;; Check if caller owns credits
(define-private (owns-credits (credit-id uint) (owner principal) (amount uint))
  (let ((balance (default-to u0 (map-get? credit-balances {credit-id: credit-id, owner: owner}))))
    (>= balance amount)))

;; Calculate platform fee
(define-private (calculate-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) PRECISION))

;; Get a new unique credit ID
(define-private (get-next-credit-id)
  (let ((current-id (var-get next-credit-id)))
    (var-set next-credit-id (+ current-id u1))
    current-id))

;; Get a new unique listing ID
(define-private (get-next-listing-id)
  (let ((current-id (var-get next-listing-id)))
    (var-set next-listing-id (+ current-id u1))
    current-id))

;; =========================================
;; Read-Only Functions
;; =========================================

;; Get issuer information
(define-read-only (get-issuer (address principal))
  (map-get? issuers address))

;; Get verifier information
(define-read-only (get-verifier (address principal))
  (map-get? verifiers address))

;; Get carbon credit information
(define-read-only (get-carbon-credit (credit-id uint))
  (map-get? carbon-credits credit-id))

;; Get credit balance for an owner
(define-read-only (get-credit-balance (credit-id uint) (owner principal))
  (default-to u0 (map-get? credit-balances {credit-id: credit-id, owner: owner})))

;; Get retirement information
(define-read-only (get-retired-credits (credit-id uint) (owner principal))
  (map-get? retired-credits {credit-id: credit-id, owner: owner}))

;; Get marketplace listing
(define-read-only (get-marketplace-listing (listing-id uint))
  (map-get? marketplace-listings listing-id))

;; Get platform fee percentage
(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage))

;; Get platform treasury
(define-read-only (get-platform-treasury)
  (var-get platform-treasury))

;; Check if credit is verified
(define-read-only (is-credit-verified (credit-id uint))
  (match (map-get? carbon-credits credit-id)
    credit-data (get is-verified credit-data)
    false))

;; =========================================
;; Admin Functions
;; =========================================

;; Add an administrator
(define-public (add-administrator (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set administrators address true))))

;; Remove an administrator
(define-public (remove-administrator (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-delete administrators address))))

;; Set platform fee percentage (input with PRECISION factor)
(define-public (set-platform-fee-percentage (new-percentage uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-percentage (* u20 PRECISION)) ERR-PLATFORM-PERCENTAGE-INVALID) ;; Max 20%
    (ok (var-set platform-fee-percentage new-percentage))))

;; Set platform treasury
(define-public (set-platform-treasury (new-treasury principal))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set platform-treasury new-treasury))))

;; =========================================
;; Issuer Management
;; =========================================

;; Register a new carbon credit issuer
(define-public (register-issuer (issuer principal) (name (string-ascii 100)))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? issuers issuer)) ERR-ISSUER-ALREADY-EXISTS)
    (ok (map-set issuers issuer {
      name: name,
      is-active: true,
      total-issued: u0,
      registration-time: block-height
    }))))

;; Update issuer status (activate/deactivate)
(define-public (update-issuer-status (issuer principal) (is-active bool))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? issuers issuer)) ERR-ISSUER-NOT-FOUND)
    (match (map-get? issuers issuer)
      issuer-data (ok (map-set issuers issuer 
        (merge issuer-data {is-active: is-active})))
      ERR-ISSUER-NOT-FOUND)))

;; =========================================
;; Verifier Management
;; =========================================

;; Register a new verification body
(define-public (register-verifier (verifier principal) (name (string-ascii 100)) (standards (list 10 (string-ascii 50))))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? verifiers verifier)) ERR-VERIFIER-ALREADY-EXISTS)
    (ok (map-set verifiers verifier {
      name: name,
      is-active: true,
      standards: standards,
      registration-time: block-height
    }))))

;; Update verifier status (activate/deactivate)
(define-public (update-verifier-status (verifier principal) (is-active bool))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? verifiers verifier)) ERR-VERIFIER-NOT-FOUND)
    (match (map-get? verifiers verifier)
      verifier-data (ok (map-set verifiers verifier 
        (merge verifier-data {is-active: is-active})))
      ERR-VERIFIER-NOT-FOUND)))

;; =========================================
;; Carbon Credit Lifecycle
;; =========================================

;; Issue new carbon credits
(define-public (issue-carbon-credits
  (vintage-year uint)
  (project-type (string-ascii 50))
  (location (string-ascii 50))
  (standard (string-ascii 50))
  (total-supply uint))
  (let 
    ((issuer tx-sender)
     (credit-id (get-next-credit-id)))
    (begin
      (asserts! (is-active-issuer issuer) ERR-NOT-AUTHORIZED)
      (asserts! (> total-supply u0) ERR-INVALID-AMOUNT)
      
      ;; Create the carbon credit record
      (map-set carbon-credits credit-id {
        issuer: issuer,
        verifier: none,
        vintage-year: vintage-year,
        project-type: project-type,
        location: location,
        standard: standard,
        total-supply: total-supply,
        is-verified: false,
        is-active: true,
        creation-time: block-height
      })
      
      ;; Update issuer's total issued credits
      (match (map-get? issuers issuer)
        issuer-data (map-set issuers issuer 
          (merge issuer-data {
            total-issued: (+ (get total-issued issuer-data) total-supply)
          }))
        (err ERR-ISSUER-NOT-FOUND))
      
      ;; Assign initial balance to the issuer
      (map-set credit-balances {credit-id: credit-id, owner: issuer} total-supply)
      
      (ok credit-id))))

;; Verify carbon credits
(define-public (verify-carbon-credit (credit-id uint))
  (let ((verifier tx-sender))
    (begin
      (asserts! (is-active-verifier verifier) ERR-NOT-AUTHORIZED)
      (asserts! (credit-exists credit-id) ERR-CREDIT-NOT-FOUND)
      
      (match (map-get? carbon-credits credit-id)
        credit-data 
          (ok (map-set carbon-credits credit-id 
            (merge credit-data {
              verifier: (some verifier),
              is-verified: true
            })))
        ERR-CREDIT-NOT-FOUND))))

;; Transfer carbon credits from one account to another
(define-public (transfer-credits (credit-id uint) (recipient principal) (amount uint))
  (let 
    ((sender tx-sender))
    (begin
      (asserts! (credit-exists credit-id) ERR-CREDIT-NOT-FOUND)
      (asserts! (owns-credits credit-id sender amount) ERR-NOT-CREDIT-OWNER)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      
      ;; Update sender balance
      (let ((sender-balance (get-credit-balance credit-id sender)))
        (map-set credit-balances 
          {credit-id: credit-id, owner: sender} 
          (- sender-balance amount)))
      
      ;; Update recipient balance
      (let ((recipient-balance (get-credit-balance credit-id recipient)))
        (map-set credit-balances 
          {credit-id: credit-id, owner: recipient} 
          (+ recipient-balance amount)))
      
      (ok true))))

;; Retire carbon credits (mark as used for offset)
(define-public (retire-credits (credit-id uint) (amount uint) (purpose (string-ascii 100)))
  (let 
    ((owner tx-sender))
    (begin
      (asserts! (credit-exists credit-id) ERR-CREDIT-NOT-FOUND)
      (asserts! (is-credit-verified credit-id) ERR-CREDIT-NOT-VERIFIED)
      (asserts! (owns-credits credit-id owner amount) ERR-NOT-CREDIT-OWNER)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      
      ;; Update owner's available balance
      (let ((owner-balance (get-credit-balance credit-id owner)))
        (map-set credit-balances 
          {credit-id: credit-id, owner: owner} 
          (- owner-balance amount)))
      
      ;; Record retirement
      (let ((existing-retirement (map-get? retired-credits {credit-id: credit-id, owner: owner})))
        (match existing-retirement
          retirement-data
            (map-set retired-credits 
              {credit-id: credit-id, owner: owner} 
              {
                amount: (+ (get amount retirement-data) amount),
                retirement-time: block-height,
                retirement-purpose: purpose
              })
          ;; No existing retirement record
          (map-set retired-credits 
            {credit-id: credit-id, owner: owner} 
            {
              amount: amount,
              retirement-time: block-height,
              retirement-purpose: purpose
            })))
      
      (ok true))))

;; =========================================
;; Marketplace Functions
;; =========================================

;; List carbon credits for sale
(define-public (list-credits (credit-id uint) (amount uint) (price-per-unit uint))
  (let 
    ((seller tx-sender)
     (listing-id (get-next-listing-id)))
    (begin
      (asserts! (credit-exists credit-id) ERR-CREDIT-NOT-FOUND)
      (asserts! (is-credit-verified credit-id) ERR-CREDIT-NOT-VERIFIED)
      (asserts! (owns-credits credit-id seller amount) ERR-NOT-CREDIT-OWNER)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      (asserts! (> price-per-unit u0) ERR-INVALID-AMOUNT)
      
      ;; Create listing
      (map-set marketplace-listings listing-id {
        seller: seller,
        credit-id: credit-id,
        amount: amount,
        price-per-unit: price-per-unit,
        is-active: true,
        listing-time: block-height
      })
      
      (ok listing-id))))

;; Cancel a listing
(define-public (cancel-listing (listing-id uint))
  (begin
    (match (map-get? marketplace-listings listing-id)
      listing 
        (begin
          (asserts! (is-eq tx-sender (get seller listing)) ERR-NOT-AUTHORIZED)
          (asserts! (get is-active listing) ERR-LISTING-NOT-FOUND)
          (ok (map-set marketplace-listings listing-id 
            (merge listing {is-active: false}))))
      ERR-LISTING-NOT-FOUND)))

;; Buy carbon credits from a listing
(define-public (buy-credits (listing-id uint) (amount uint))
  (let 
    ((buyer tx-sender))
    (match (map-get? marketplace-listings listing-id)
      listing
        (let
          ((seller (get seller listing))
           (credit-id (get credit-id listing))
           (available-amount (get amount listing))
           (price-per-unit (get price-per-unit listing))
           (is-active (get is-active listing))
           (total-price (* amount price-per-unit))
           (platform-fee (calculate-fee total-price)))
          (begin
            (asserts! is-active ERR-LISTING-NOT-FOUND)
            (asserts! (<= amount available-amount) ERR-INVALID-AMOUNT)
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            
            ;; Check buyer has enough STX
            (asserts! (>= (stx-get-balance buyer) total-price) ERR-INSUFFICIENT-FUNDS)
            
            ;; Transfer STX from buyer to seller and platform
            (try! (stx-transfer? (- total-price platform-fee) buyer seller))
            (try! (stx-transfer? platform-fee buyer (var-get platform-treasury)))
            
            ;; Transfer credits
            (try! (transfer-credits credit-id seller buyer amount))
            
            ;; Update listing
            (if (< amount available-amount)
              ;; Partial purchase - update listing amount
              (map-set marketplace-listings listing-id 
                (merge listing {amount: (- available-amount amount)}))
              ;; Complete purchase - deactivate listing
              (map-set marketplace-listings listing-id 
                (merge listing {amount: u0, is-active: false}))
            )
            
            (ok true)))
      ERR-LISTING-NOT-FOUND)))