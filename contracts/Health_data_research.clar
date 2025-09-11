;; title: Health_data_research
;; version: 1.0.0
;; summary: Decentralized health data donation and research marketplace
;; description: Enables patients to donate anonymized health data and researchers to access verified datasets

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-expired (err u106))
(define-constant err-invalid-status (err u107))
(define-constant err-already-rated (err u108))
(define-constant err-no-access (err u109))
(define-constant err-invalid-rating (err u110))

(define-data-var next-dataset-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var platform-fee-rate uint u250)
(define-data-var min-compensation uint u1000000)
(define-data-var data-retention-blocks uint u144000)

(define-map datasets
  { dataset-id: uint }
  {
    donor: principal,
    data-hash: (buff 32),
    data-type: (string-ascii 50),
    timestamp: uint,
    compensation: uint,
    access-count: uint,
    verified: bool,
    active: bool,
    quality-score: uint,
    total-ratings: uint
  }
)

(define-map research-requests
  { request-id: uint }
  {
    researcher: principal,
    data-type: (string-ascii 50),
    purpose: (string-ascii 200),
    payment-amount: uint,
    expiry-block: uint,
    fulfilled: bool,
    dataset-id: (optional uint)
  }
)

(define-map researcher-profiles
  { researcher: principal }
  {
    institution: (string-ascii 100),
    verified: bool,
    reputation-score: uint,
    total-requests: uint,
    successful-requests: uint
  }
)

(define-map donor-stats
  { donor: principal }
  {
    total-donations: uint,
    total-earnings: uint,
    reputation-score: uint,
    anonymous-id: (buff 20)
  }
)

(define-map dataset-access
  { dataset-id: uint, researcher: principal }
  {
    access-granted: bool,
    access-timestamp: uint,
    payment-made: uint
  }
)

(define-map quality-ratings
  { dataset-id: uint, researcher: principal }
  {
    rating: uint,
    feedback: (string-ascii 200),
    timestamp: uint
  }
)

(define-public (register-researcher (institution (string-ascii 100)))
  (let ((existing (map-get? researcher-profiles { researcher: tx-sender })))
    (if (is-some existing)
      err-already-exists
      (ok (map-set researcher-profiles
        { researcher: tx-sender }
        {
          institution: institution,
          verified: false,
          reputation-score: u100,
          total-requests: u0,
          successful-requests: u0
        }
      ))
    )
  )
)

(define-public (verify-researcher (researcher principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? researcher-profiles { researcher: researcher })
      profile (ok (map-set researcher-profiles
        { researcher: researcher }
        (merge profile { verified: true })
      ))
      err-not-found
    )
  )
)

(define-public (donate-health-data 
  (data-hash (buff 32))
  (data-type (string-ascii 50))
  (min-compensation-required uint))
  (let (
    (dataset-id (var-get next-dataset-id))
    (anonymous-id (unwrap-panic (as-max-len? (sha256 (concat (unwrap-panic (to-consensus-buff? tx-sender)) (unwrap-panic (to-consensus-buff? stacks-block-height)))) u20)))
  )
    (asserts! (>= min-compensation-required (var-get min-compensation)) err-invalid-data)
    (var-set next-dataset-id (+ dataset-id u1))
    (map-set datasets
      { dataset-id: dataset-id }
      {
        donor: tx-sender,
        data-hash: data-hash,
        data-type: data-type,
        timestamp: stacks-block-height,
        compensation: min-compensation-required,
        access-count: u0,
        verified: false,
        active: true,
        quality-score: u0,
        total-ratings: u0
      }
    )
    (match (map-get? donor-stats { donor: tx-sender })
      stats (map-set donor-stats
        { donor: tx-sender }
        {
          total-donations: (+ (get total-donations stats) u1),
          total-earnings: (get total-earnings stats),
          reputation-score: (if (> (+ (get reputation-score stats) u10) u1000) u1000 (+ (get reputation-score stats) u10)),
          anonymous-id: (get anonymous-id stats)
        }
      )
      (map-set donor-stats
        { donor: tx-sender }
        {
          total-donations: u1,
          total-earnings: u0,
          reputation-score: u110,
          anonymous-id: anonymous-id
        }
      )
    )
    (ok dataset-id)
  )
)

(define-public (verify-dataset (dataset-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? datasets { dataset-id: dataset-id })
      dataset (ok (map-set datasets
        { dataset-id: dataset-id }
        (merge dataset { verified: true })
      ))
      err-not-found
    )
  )
)

(define-public (create-research-request
  (data-type (string-ascii 50))
  (purpose (string-ascii 200))
  (payment-amount uint)
  (duration-blocks uint))
  (let (
    (request-id (var-get next-request-id))
    (expiry-block (+ stacks-block-height duration-blocks))
  )
    (asserts! (>= payment-amount (var-get min-compensation)) err-insufficient-payment)
    (match (map-get? researcher-profiles { researcher: tx-sender })
      profile (begin
        (asserts! (get verified profile) err-unauthorized)
        (var-set next-request-id (+ request-id u1))
        (map-set research-requests
          { request-id: request-id }
          {
            researcher: tx-sender,
            data-type: data-type,
            purpose: purpose,
            payment-amount: payment-amount,
            expiry-block: expiry-block,
            fulfilled: false,
            dataset-id: none
          }
        )
        (map-set researcher-profiles
          { researcher: tx-sender }
          (merge profile { total-requests: (+ (get total-requests profile) u1) })
        )
        (ok request-id)
      )
      err-not-found
    )
  )
)

(define-public (purchase-dataset-access (dataset-id uint) (request-id uint))
  (let (
    (dataset (unwrap! (map-get? datasets { dataset-id: dataset-id }) err-not-found))
    (request (unwrap! (map-get? research-requests { request-id: request-id }) err-not-found))
    (researcher-profile (unwrap! (map-get? researcher-profiles { researcher: tx-sender }) err-not-found))
    (platform-fee (/ (* (get payment-amount request) (var-get platform-fee-rate)) u10000))
    (compensation (- (get payment-amount request) platform-fee))
  )
    (asserts! (is-eq tx-sender (get researcher request)) err-unauthorized)
    (asserts! (get verified dataset) err-invalid-data)
    (asserts! (get active dataset) err-invalid-data)
    (asserts! (get verified researcher-profile) err-unauthorized)
    (asserts! (not (get fulfilled request)) err-invalid-status)
    (asserts! (< stacks-block-height (get expiry-block request)) err-expired)
    (asserts! (is-eq (get data-type dataset) (get data-type request)) err-invalid-data)
    (asserts! (>= (get payment-amount request) (get compensation dataset)) err-insufficient-payment)
    
    (try! (stx-transfer? (get payment-amount request) tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? compensation tx-sender (get donor dataset))))
    
    (map-set dataset-access
      { dataset-id: dataset-id, researcher: tx-sender }
      {
        access-granted: true,
        access-timestamp: stacks-block-height,
        payment-made: (get payment-amount request)
      }
    )
    
    (map-set datasets
      { dataset-id: dataset-id }
      (merge dataset { access-count: (+ (get access-count dataset) u1) })
    )
    
    (map-set research-requests
      { request-id: request-id }
      (merge request { fulfilled: true, dataset-id: (some dataset-id) })
    )
    
    (map-set researcher-profiles
      { researcher: tx-sender }
      (merge researcher-profile { successful-requests: (+ (get successful-requests researcher-profile) u1) })
    )
    
    (match (map-get? donor-stats { donor: (get donor dataset) })
      stats (map-set donor-stats
        { donor: (get donor dataset) }
        (merge stats { 
          total-earnings: (+ (get total-earnings stats) compensation),
          reputation-score: (if (> (+ (get reputation-score stats) u5) u1000) u1000 (+ (get reputation-score stats) u5))
        })
      )
      true
    )
    
    (ok { dataset-id: dataset-id, access-granted: true })
  )
)

(define-public (rate-dataset-quality 
  (dataset-id uint) 
  (rating uint) 
  (feedback (string-ascii 200)))
  (let (
    (dataset (unwrap! (map-get? datasets { dataset-id: dataset-id }) err-not-found))
    (access-record (unwrap! (map-get? dataset-access { dataset-id: dataset-id, researcher: tx-sender }) err-no-access))
    (existing-rating (map-get? quality-ratings { dataset-id: dataset-id, researcher: tx-sender }))
  )
    (asserts! (>= rating u1) err-invalid-rating)
    (asserts! (<= rating u5) err-invalid-rating)
    (asserts! (get access-granted access-record) err-no-access)
    (asserts! (is-none existing-rating) err-already-rated)
    
    (map-set quality-ratings
      { dataset-id: dataset-id, researcher: tx-sender }
      {
        rating: rating,
        feedback: feedback,
        timestamp: stacks-block-height
      }
    )
    
    (let (
      (current-total-score (* (get quality-score dataset) (get total-ratings dataset)))
      (new-total-ratings (+ (get total-ratings dataset) u1))
      (new-total-score (+ current-total-score rating))
      (new-average-score (/ new-total-score new-total-ratings))
    )
      (map-set datasets
        { dataset-id: dataset-id }
        (merge dataset { 
          quality-score: new-average-score,
          total-ratings: new-total-ratings
        })
      )
    )
    
    (ok rating)
  )
)

(define-public (update-researcher-reputation (researcher principal) (score-change int))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? researcher-profiles { researcher: researcher })
      profile (let ((new-score (if (> score-change 0)
                                  (if (> (+ (get reputation-score profile) (to-uint score-change)) u1000) u1000 (+ (get reputation-score profile) (to-uint score-change)))
                                  (if (> (get reputation-score profile) (to-uint (- 0 score-change)))
                                    (- (get reputation-score profile) (to-uint (- 0 score-change)))
                                    u0))))
        (ok (map-set researcher-profiles
          { researcher: researcher }
          (merge profile { reputation-score: new-score })
        ))
      )
      err-not-found
    )
  )
)

(define-public (deactivate-dataset (dataset-id uint))
  (let ((dataset (unwrap! (map-get? datasets { dataset-id: dataset-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get donor dataset)) err-unauthorized)
    (ok (map-set datasets
      { dataset-id: dataset-id }
      (merge dataset { active: false })
    ))
  )
)

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-data)
    (ok (var-set platform-fee-rate new-rate))
  )
)

(define-public (set-min-compensation (new-min uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set min-compensation new-min))
  )
)

(define-public (withdraw-platform-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)

(define-read-only (get-dataset (dataset-id uint))
  (map-get? datasets { dataset-id: dataset-id })
)

(define-read-only (get-research-request (request-id uint))
  (map-get? research-requests { request-id: request-id })
)

(define-read-only (get-researcher-profile (researcher principal))
  (map-get? researcher-profiles { researcher: researcher })
)

(define-read-only (get-donor-stats (donor principal))
  (map-get? donor-stats { donor: donor })
)

(define-read-only (get-dataset-access (dataset-id uint) (researcher principal))
  (map-get? dataset-access { dataset-id: dataset-id, researcher: researcher })
)

(define-read-only (get-quality-rating (dataset-id uint) (researcher principal))
  (map-get? quality-ratings { dataset-id: dataset-id, researcher: researcher })
)

(define-read-only (get-dataset-quality-summary (dataset-id uint))
  (match (map-get? datasets { dataset-id: dataset-id })
    dataset {
      dataset-id: dataset-id,
      quality-score: (get quality-score dataset),
      total-ratings: (get total-ratings dataset),
      access-count: (get access-count dataset),
      data-type: (get data-type dataset)
    }
    {
      dataset-id: u0,
      quality-score: u0,
      total-ratings: u0,
      access-count: u0,
      data-type: ""
    }
  )
)

(define-read-only (get-high-quality-datasets (min-quality uint))
  (get results (fold check-quality-threshold (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { min-quality: min-quality, results: (list) }))
)

(define-private (check-quality-threshold (dataset-id uint) (context { min-quality: uint, results: (list 20 uint) }))
  (let ((dataset (map-get? datasets { dataset-id: dataset-id })))
    (if (and (is-some dataset)
             (get verified (unwrap-panic dataset))
             (get active (unwrap-panic dataset))
             (> (get total-ratings (unwrap-panic dataset)) u0)
             (>= (get quality-score (unwrap-panic dataset)) (get min-quality context)))
      { 
        min-quality: (get min-quality context), 
        results: (unwrap-panic (as-max-len? (append (get results context) dataset-id) u20))
      }
      context
    )
  )
)

(define-read-only (get-platform-stats)
  {
    total-datasets: (- (var-get next-dataset-id) u1),
    total-requests: (- (var-get next-request-id) u1),
    platform-fee-rate: (var-get platform-fee-rate),
    min-compensation: (var-get min-compensation),
    current-block: stacks-block-height
  }
)

(define-read-only (check-dataset-eligibility (dataset-id uint) (researcher principal))
  (match (map-get? datasets { dataset-id: dataset-id })
    dataset (match (map-get? researcher-profiles { researcher: researcher })
      profile {
        dataset-verified: (get verified dataset),
        dataset-active: (get active dataset),
        researcher-verified: (get verified profile),
        data-type: (get data-type dataset),
        required-compensation: (get compensation dataset),
        access-count: (get access-count dataset),
        quality-score: (get quality-score dataset),
        total-ratings: (get total-ratings dataset)
      }
      { dataset-verified: false, dataset-active: false, researcher-verified: false, data-type: "", required-compensation: u0, access-count: u0, quality-score: u0, total-ratings: u0 }
    )
    { dataset-verified: false, dataset-active: false, researcher-verified: false, data-type: "", required-compensation: u0, access-count: u0, quality-score: u0, total-ratings: u0 }
  )
)

(define-read-only (get-matching-datasets (data-type (string-ascii 50)) (max-compensation uint))
  (filter-datasets data-type max-compensation)
)

(define-private (filter-datasets (data-type (string-ascii 50)) (max-compensation uint))
  (let ((current-id (var-get next-dataset-id)))
    (fold check-dataset-match (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) (list))
  )
)

(define-private (check-dataset-match (dataset-id uint) (acc (list 20 uint)))
  (let ((dataset (map-get? datasets { dataset-id: dataset-id })))
    (if (and (is-some dataset)
             (get verified (unwrap-panic dataset))
             (get active (unwrap-panic dataset)))
      (unwrap-panic (as-max-len? (append acc dataset-id) u20))
      acc
    )
  )
)

(define-public (batch-verify-datasets (dataset-ids (list 20 uint)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map verify-single-dataset dataset-ids))
  )
)

(define-private (verify-single-dataset (dataset-id uint))
  (match (map-get? datasets { dataset-id: dataset-id })
    dataset (map-set datasets
      { dataset-id: dataset-id }
      (merge dataset { verified: true })
    )
    false
  )
)

(define-read-only (calculate-researcher-score (researcher principal))
  (match (map-get? researcher-profiles { researcher: researcher })
    profile (let (
      (success-rate (if (> (get total-requests profile) u0)
                      (/ (* (get successful-requests profile) u100) (get total-requests profile))
                      u0))
      (base-score (get reputation-score profile))
    )
      (+ base-score success-rate)
    )
    u0
  )
)

(define-read-only (get-expired-requests)
  (fold check-expired-request (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) (list))
)

(define-private (check-expired-request (request-id uint) (acc (list 20 uint)))
  (let ((request (map-get? research-requests { request-id: request-id })))
    (if (and (is-some request)
             (< (get expiry-block (unwrap-panic request)) stacks-block-height)
             (not (get fulfilled (unwrap-panic request))))
      (unwrap-panic (as-max-len? (append acc request-id) u20))
      acc
    )
  )
)

(define-public (cleanup-expired-data)
  (let (
    (retention-limit (- stacks-block-height (var-get data-retention-blocks)))
  )
    (ok (fold cleanup-single-dataset (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) u0))
  )
)

(define-private (cleanup-single-dataset (dataset-id uint) (acc uint))
  (let (
    (dataset (map-get? datasets { dataset-id: dataset-id }))
    (retention-limit (- stacks-block-height (var-get data-retention-blocks)))
  )
    (if (and (is-some dataset)
             (< (get timestamp (unwrap-panic dataset)) retention-limit))
      (begin
        (map-delete datasets { dataset-id: dataset-id })
        (+ acc u1)
      )
      acc
    )
  )
)

(define-read-only (get-researcher-dashboard (researcher principal))
  (match (map-get? researcher-profiles { researcher: researcher })
    profile {
      profile: profile,
      active-requests: (get count (fold count-researcher-requests (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { researcher: researcher, count: u0 })),
      success-rate: (if (> (get total-requests profile) u0)
                      (/ (* (get successful-requests profile) u100) (get total-requests profile))
                      u0),
      calculated-score: (calculate-researcher-score researcher)
    }
    { 
      profile: {
        institution: "",
        verified: false,
        reputation-score: u0,
        total-requests: u0,
        successful-requests: u0
      }, 
      active-requests: u0, 
      success-rate: u0, 
      calculated-score: u0 
    }
  )
)

(define-private (count-researcher-requests (request-id uint) (context { researcher: principal, count: uint }))
  (let ((request (map-get? research-requests { request-id: request-id })))
    (if (and (is-some request)
             (is-eq (get researcher (unwrap-panic request)) (get researcher context))
             (not (get fulfilled (unwrap-panic request)))
             (>= (get expiry-block (unwrap-panic request)) stacks-block-height))
      { researcher: (get researcher context), count: (+ (get count context) u1) }
      context
    )
  )
)

(define-read-only (get-donor-dashboard (donor principal))
  (match (map-get? donor-stats { donor: donor })
    stats {
      stats: stats,
      active-datasets: (get count (fold count-donor-datasets (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) { donor: donor, count: u0 })),
      avg-compensation: (if (> (get total-donations stats) u0)
                          (/ (get total-earnings stats) (get total-donations stats))
                          u0)
    }
    { 
      stats: {
        total-donations: u0,
        total-earnings: u0,
        reputation-score: u0,
        anonymous-id: 0x00000000000000000000000000000000000000
      }, 
      active-datasets: u0, 
      avg-compensation: u0 
    }
  )
)

(define-private (count-donor-datasets (dataset-id uint) (context { donor: principal, count: uint }))
  (let ((dataset (map-get? datasets { dataset-id: dataset-id })))
    (if (and (is-some dataset)
             (is-eq (get donor (unwrap-panic dataset)) (get donor context))
             (get active (unwrap-panic dataset)))
      { donor: (get donor context), count: (+ (get count context) u1) }
      context
    )
  )
)
