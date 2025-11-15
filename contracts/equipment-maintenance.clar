;; Equipment Maintenance Management Contract
;; Handles sensor data integration, failure prediction, maintenance scheduling, and cost optimization

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-EQUIPMENT (err u101))
(define-constant ERR-INVALID-SENSOR-DATA (err u102))
(define-constant ERR-INVALID-MAINTENANCE (err u103))
(define-constant MAX-SENSOR-READINGS u1000)
(define-constant FAILURE-THRESHOLD u80)

(define-data-var equipment-counter uint u0)
(define-data-var total-maintenance-cost uint u0)

(define-map equipment
  { equipment-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    status: (string-ascii 16),
    failure-risk: uint,
    total-hours: uint,
    last-maintenance: uint,
    created-at: uint
  }
)

(define-map sensor-readings
  { equipment-id: uint, reading-id: uint }
  {
    temperature: uint,
    vibration: uint,
    pressure: uint,
    timestamp: uint
  }
)

(define-map maintenance-schedule
  { maintenance-id: uint }
  {
    equipment-id: uint,
    scheduled-date: uint,
    estimated-cost: uint,
    status: (string-ascii 16),
    completion-date: (optional uint)
  }
)

(define-map sensor-count
  { equipment-id: uint }
  { count: uint }
)

(define-public (register-equipment (name (string-ascii 64)))
  (let
    (
      (new-id (+ (var-get equipment-counter) u1))
    )
    (map-set equipment
      { equipment-id: new-id }
      {
        owner: tx-sender,
        name: name,
        status: "active",
        failure-risk: u0,
        total-hours: u0,
        last-maintenance: burn-block-height,
        created-at: burn-block-height
      }
    )
    (var-set equipment-counter new-id)
    (ok new-id)
  )
)

(define-public (record-sensor-reading
  (equipment-id uint)
  (temperature uint)
  (vibration uint)
  (pressure uint)
)
  (let
    (
      (eq (map-get? equipment { equipment-id: equipment-id }))
      (sensor-map (map-get? sensor-count { equipment-id: equipment-id }))
      (current-count (match sensor-map count-map (get count count-map) u0))
    )
    (match eq
      equipment-data
      (begin
        (asserts! (< current-count MAX-SENSOR-READINGS) ERR-INVALID-SENSOR-DATA)
        (asserts! (<= temperature u200) ERR-INVALID-SENSOR-DATA)
        (asserts! (<= vibration u100) ERR-INVALID-SENSOR-DATA)
        (asserts! (<= pressure u300) ERR-INVALID-SENSOR-DATA)
        (map-set sensor-readings
          { equipment-id: equipment-id, reading-id: current-count }
          {
            temperature: temperature,
            vibration: vibration,
            pressure: pressure,
            timestamp: burn-block-height
          }
        )
        (map-set sensor-count
          { equipment-id: equipment-id }
          { count: (+ current-count u1) }
        )
        (ok true)
      )
      ERR-INVALID-EQUIPMENT
    )
  )
)

(define-public (predict-failure (equipment-id uint))
  (let
    (
      (eq (map-get? equipment { equipment-id: equipment-id }))
    )
    (match eq
      equipment-data
      (let
        (
          (risk-score (calculate-failure-risk equipment-id))
        )
        (map-set equipment
          { equipment-id: equipment-id }
          (merge equipment-data { failure-risk: risk-score })
        )
        (ok risk-score)
      )
      ERR-INVALID-EQUIPMENT
    )
  )
)

(define-public (schedule-maintenance
  (equipment-id uint)
  (scheduled-date uint)
  (estimated-cost uint)
)
  (let
    (
      (eq (map-get? equipment { equipment-id: equipment-id }))
      (maintenance-id (+ equipment-id burn-block-height))
    )
    (match eq
      equipment-data
      (begin
        (asserts! (> scheduled-date burn-block-height) ERR-INVALID-MAINTENANCE)
        (map-set maintenance-schedule
          { maintenance-id: maintenance-id }
          {
            equipment-id: equipment-id,
            scheduled-date: scheduled-date,
            estimated-cost: estimated-cost,
            status: "scheduled",
            completion-date: none
          }
        )
        (ok maintenance-id)
      )
      ERR-INVALID-EQUIPMENT
    )
  )
)

(define-public (complete-maintenance (maintenance-id uint) (actual-cost uint))
  (let
    (
      (maint (map-get? maintenance-schedule { maintenance-id: maintenance-id }))
    )
    (match maint
      maintenance-data
      (begin
        (map-set maintenance-schedule
          { maintenance-id: maintenance-id }
          (merge maintenance-data
            {
              status: "completed",
              completion-date: (some burn-block-height)
            }
          )
        )
        (var-set total-maintenance-cost (+ (var-get total-maintenance-cost) actual-cost))
        (ok true)
      )
      ERR-INVALID-MAINTENANCE
    )
  )
)

(define-public (update-equipment-status (equipment-id uint) (new-status (string-ascii 16)))
  (let
    (
      (eq (map-get? equipment { equipment-id: equipment-id }))
    )
    (match eq
      equipment-data
      (begin
        (asserts! (is-eq tx-sender (get owner equipment-data)) ERR-UNAUTHORIZED)
        (map-set equipment
          { equipment-id: equipment-id }
          (merge equipment-data { status: new-status })
        )
        (ok true)
      )
      ERR-INVALID-EQUIPMENT
    )
  )
)

(define-private (calculate-failure-risk (equipment-id uint))
  (let
    (
      (reading-count (get count (default-to { count: u0 } (map-get? sensor-count { equipment-id: equipment-id }))))
    )
    (if (> reading-count u0)
      (let
        (
          (base-risk (/ (* reading-count u10) MAX-SENSOR-READINGS))
        )
        (if (> base-risk FAILURE-THRESHOLD)
          FAILURE-THRESHOLD
          base-risk
        )
      )
      u0
    )
  )
)

(define-read-only (get-equipment (equipment-id uint))
  (map-get? equipment { equipment-id: equipment-id })
)

(define-read-only (get-sensor-reading (equipment-id uint) (reading-id uint))
  (map-get? sensor-readings { equipment-id: equipment-id, reading-id: reading-id })
)

(define-read-only (get-maintenance-schedule (maintenance-id uint))
  (map-get? maintenance-schedule { maintenance-id: maintenance-id })
)

(define-read-only (get-total-maintenance-cost)
  (var-get total-maintenance-cost)
)

(define-read-only (get-equipment-count)
  (var-get equipment-counter)
)

