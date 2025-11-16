;; Serious Event Reporter Contract
;; Manages serious adverse event reporting, causality assessment, and regulatory compliance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-event-not-found (err u102))
(define-constant err-invalid-event (err u103))
(define-constant err-report-not-found (err u104))
(define-constant err-already-reported (err u105))
(define-constant err-invalid-parameters (err u106))
(define-constant err-deadline-passed (err u107))
(define-constant err-assessment-not-found (err u108))

;; Seriousness criteria constants
(define-constant criteria-death u1)
(define-constant criteria-life-threatening u2)
(define-constant criteria-hospitalization u3)
(define-constant criteria-disability u4)
(define-constant criteria-congenital-anomaly u5)
(define-constant criteria-other-serious u6)

;; Causality relationship constants
(define-constant causality-unrelated u0)
(define-constant causality-unlikely u1)
(define-constant causality-possible u2)
(define-constant causality-probable u3)
(define-constant causality-definite u4)

;; Outcome status constants
(define-constant outcome-recovered u1)
(define-constant outcome-recovering u2)
(define-constant outcome-not-recovered u3)
(define-constant outcome-sequelae u4)
(define-constant outcome-fatal u5)
(define-constant outcome-unknown u6)

;; Report type constants
(define-constant report-initial u1)
(define-constant report-followup u2)
(define-constant report-final u3)

;; Deadline type constants
(define-constant deadline-7-day u7)
(define-constant deadline-15-day u15)

;; Data Variables
(define-data-var event-nonce uint u0)
(define-data-var assessment-nonce uint u0)
(define-data-var report-nonce uint u0)
(define-data-var notification-nonce uint u0)
(define-data-var submission-nonce uint u0)

;; Authorization Maps
(define-map site-coordinators principal bool)
(define-map medical-reviewers principal bool)
(define-map regulatory-staff principal bool)
(define-map sponsors principal bool)

;; Serious Adverse Events
(define-map serious-adverse-events
  uint
  {
    patient-id: (string-ascii 50),
    event-description: (string-ascii 500),
    diagnosis: (string-ascii 200),
    onset-date: uint,
    resolution-date: uint,
    seriousness-criteria: uint,
    severity-grade: uint,
    is-expected: bool,
    outcome-status: uint,
    site-id: (string-ascii 50),
    coordinator: principal,
    reported-date: uint,
    active: bool
  }
)

;; Causality Assessments
(define-map causality-assessments
  uint
  {
    event-id: uint,
    relationship: uint,
    naranjo-score: uint,
    reviewer: principal,
    assessment-date: uint,
    rationale: (string-ascii 1000),
    alternative-causes: (string-ascii 500),
    rechallenge-result: (optional bool)
  }
)

;; Expedited Reports
(define-map expedited-reports
  uint
  {
    event-id: uint,
    report-type: uint,
    version: uint,
    deadline-days: uint,
    submission-deadline: uint,
    report-data: (string-ascii 2000),
    status: (string-ascii 50),
    created-by: principal,
    created-date: uint,
    submitted: bool
  }
)

;; Sponsor Notifications
(define-map sponsor-notifications
  uint
  {
    event-id: uint,
    report-id: uint,
    sponsor: principal,
    notification-time: uint,
    method: (string-ascii 100),
    acknowledged: bool,
    acknowledgment-time: uint
  }
)

;; Regulatory Submissions
(define-map regulatory-submissions
  uint
  {
    report-id: uint,
    authority: (string-ascii 100),
    submission-date: uint,
    submission-method: (string-ascii 100),
    confirmation-number: (string-ascii 100),
    accepted: bool,
    acceptance-date: uint,
    submitter: principal
  }
)

;; Event Reports Mapping (event-id to list of report-ids)
(define-map event-reports uint (list 20 uint))

;; Site Statistics
(define-map site-stats
  (string-ascii 50)
  {
    total-events: uint,
    fatal-events: uint,
    life-threatening-events: uint,
    pending-reports: uint,
    last-event-date: uint
  }
)

;; Authorization Functions
(define-public (add-site-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set site-coordinators coordinator true))
  )
)

(define-public (add-medical-reviewer (reviewer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set medical-reviewers reviewer true))
  )
)

(define-public (add-regulatory-staff (staff principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set regulatory-staff staff true))
  )
)

(define-public (add-sponsor (sponsor principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set sponsors sponsor true))
  )
)

(define-public (remove-site-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete site-coordinators coordinator))
  )
)

(define-public (remove-medical-reviewer (reviewer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete medical-reviewers reviewer))
  )
)

(define-public (remove-regulatory-staff (staff principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete regulatory-staff staff))
  )
)

(define-public (remove-sponsor (sponsor principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete sponsors sponsor))
  )
)

;; Event Management Functions
(define-public (report-serious-adverse-event
  (patient-id (string-ascii 50))
  (description (string-ascii 500))
  (diagnosis (string-ascii 200))
  (onset-date uint)
  (seriousness uint)
  (severity uint)
  (is-expected bool)
  (site-id (string-ascii 50))
)
  (let
    (
      (event-id (+ (var-get event-nonce) u1))
      (site-data (default-to
        { total-events: u0, fatal-events: u0, life-threatening-events: u0, pending-reports: u0, last-event-date: u0 }
        (map-get? site-stats site-id)
      ))
    )
    (asserts! (default-to false (map-get? site-coordinators tx-sender)) err-not-authorized)
    (asserts! (and (>= seriousness criteria-death) (<= seriousness criteria-other-serious)) err-invalid-parameters)
    (asserts! (and (>= severity u1) (<= severity u5)) err-invalid-parameters)
    (map-set serious-adverse-events event-id
      {
        patient-id: patient-id,
        event-description: description,
        diagnosis: diagnosis,
        onset-date: onset-date,
        resolution-date: u0,
        seriousness-criteria: seriousness,
        severity-grade: severity,
        is-expected: is-expected,
        outcome-status: outcome-unknown,
        site-id: site-id,
        coordinator: tx-sender,
        reported-date: block-height,
        active: true
      }
    )
    (map-set site-stats site-id
      (merge site-data
        {
          total-events: (+ (get total-events site-data) u1),
          fatal-events: (if (is-eq seriousness criteria-death)
            (+ (get fatal-events site-data) u1)
            (get fatal-events site-data)
          ),
          life-threatening-events: (if (is-eq seriousness criteria-life-threatening)
            (+ (get life-threatening-events site-data) u1)
            (get life-threatening-events site-data)
          ),
          pending-reports: (+ (get pending-reports site-data) u1),
          last-event-date: block-height
        }
      )
    )
    (map-set event-reports event-id (list))
    (var-set event-nonce event-id)
    (ok event-id)
  )
)

(define-public (update-event-outcome (event-id uint) (resolution-date uint) (outcome uint))
  (let
    (
      (event (unwrap! (map-get? serious-adverse-events event-id) err-event-not-found))
    )
    (asserts! (default-to false (map-get? site-coordinators tx-sender)) err-not-authorized)
    (asserts! (get active event) err-invalid-event)
    (asserts! (and (>= outcome outcome-recovered) (<= outcome outcome-unknown)) err-invalid-parameters)
    (ok (map-set serious-adverse-events event-id
      (merge event
        {
          resolution-date: resolution-date,
          outcome-status: outcome
        }
      )
    ))
  )
)

;; Causality Assessment Functions
(define-public (perform-causality-assessment
  (event-id uint)
  (relationship uint)
  (naranjo uint)
  (rationale (string-ascii 1000))
  (alternatives (string-ascii 500))
  (rechallenge (optional bool))
)
  (let
    (
      (assessment-id (+ (var-get assessment-nonce) u1))
      (event (unwrap! (map-get? serious-adverse-events event-id) err-event-not-found))
    )
    (asserts! (default-to false (map-get? medical-reviewers tx-sender)) err-not-authorized)
    (asserts! (get active event) err-invalid-event)
    (asserts! (and (>= relationship causality-unrelated) (<= relationship causality-definite)) err-invalid-parameters)
    (asserts! (<= naranjo u13) err-invalid-parameters)
    (map-set causality-assessments assessment-id
      {
        event-id: event-id,
        relationship: relationship,
        naranjo-score: naranjo,
        reviewer: tx-sender,
        assessment-date: block-height,
        rationale: rationale,
        alternative-causes: alternatives,
        rechallenge-result: rechallenge
      }
    )
    (var-set assessment-nonce assessment-id)
    (ok assessment-id)
  )
)

;; Reporting Functions
(define-public (generate-expedited-report
  (event-id uint)
  (report-type uint)
  (deadline-days uint)
  (report-data (string-ascii 2000))
)
  (let
    (
      (report-id (+ (var-get report-nonce) u1))
      (event (unwrap! (map-get? serious-adverse-events event-id) err-event-not-found))
      (current-reports (default-to (list) (map-get? event-reports event-id)))
    )
    (asserts! (default-to false (map-get? regulatory-staff tx-sender)) err-not-authorized)
    (asserts! (get active event) err-invalid-event)
    (asserts! (and (>= report-type report-initial) (<= report-type report-final)) err-invalid-parameters)
    (asserts! (or (is-eq deadline-days deadline-7-day) (is-eq deadline-days deadline-15-day)) err-invalid-parameters)
    (map-set expedited-reports report-id
      {
        event-id: event-id,
        report-type: report-type,
        version: u1,
        deadline-days: deadline-days,
        submission-deadline: (+ (get reported-date event) deadline-days),
        report-data: report-data,
        status: "pending",
        created-by: tx-sender,
        created-date: block-height,
        submitted: false
      }
    )
    (map-set event-reports event-id (unwrap-panic (as-max-len? (append current-reports report-id) u20)))
    (var-set report-nonce report-id)
    (ok report-id)
  )
)

(define-public (submit-to-sponsor (event-id uint) (report-id uint) (sponsor principal) (method (string-ascii 100)))
  (let
    (
      (notification-id (+ (var-get notification-nonce) u1))
      (event (unwrap! (map-get? serious-adverse-events event-id) err-event-not-found))
      (report (unwrap! (map-get? expedited-reports report-id) err-report-not-found))
    )
    (asserts! (default-to false (map-get? regulatory-staff tx-sender)) err-not-authorized)
    (asserts! (get active event) err-invalid-event)
    (asserts! (is-eq (get event-id report) event-id) err-invalid-parameters)
    (map-set sponsor-notifications notification-id
      {
        event-id: event-id,
        report-id: report-id,
        sponsor: sponsor,
        notification-time: block-height,
        method: method,
        acknowledged: false,
        acknowledgment-time: u0
      }
    )
    (var-set notification-nonce notification-id)
    (ok notification-id)
  )
)

(define-public (file-regulatory-submission
  (report-id uint)
  (authority (string-ascii 100))
  (method (string-ascii 100))
  (confirmation (string-ascii 100))
)
  (let
    (
      (submission-id (+ (var-get submission-nonce) u1))
      (report (unwrap! (map-get? expedited-reports report-id) err-report-not-found))
    )
    (asserts! (default-to false (map-get? regulatory-staff tx-sender)) err-not-authorized)
    (asserts! (< block-height (get submission-deadline report)) err-deadline-passed)
    (map-set regulatory-submissions submission-id
      {
        report-id: report-id,
        authority: authority,
        submission-date: block-height,
        submission-method: method,
        confirmation-number: confirmation,
        accepted: false,
        acceptance-date: u0,
        submitter: tx-sender
      }
    )
    (map-set expedited-reports report-id
      (merge report
        {
          status: "submitted",
          submitted: true
        }
      )
    )
    (var-set submission-nonce submission-id)
    (ok submission-id)
  )
)

(define-public (acknowledge-sponsor-notification (notification-id uint))
  (let
    (
      (notification (unwrap! (map-get? sponsor-notifications notification-id) err-report-not-found))
    )
    (asserts! (default-to false (map-get? sponsors tx-sender)) err-not-authorized)
    (asserts! (not (get acknowledged notification)) err-already-reported)
    (ok (map-set sponsor-notifications notification-id
      (merge notification
        {
          acknowledged: true,
          acknowledgment-time: block-height
        }
      )
    ))
  )
)

(define-public (confirm-submission-acceptance (submission-id uint))
  (let
    (
      (submission (unwrap! (map-get? regulatory-submissions submission-id) err-report-not-found))
    )
    (asserts! (default-to false (map-get? regulatory-staff tx-sender)) err-not-authorized)
    (ok (map-set regulatory-submissions submission-id
      (merge submission
        {
          accepted: true,
          acceptance-date: block-height
        }
      )
    ))
  )
)

(define-public (update-report-status (report-id uint) (new-status (string-ascii 50)))
  (let
    (
      (report (unwrap! (map-get? expedited-reports report-id) err-report-not-found))
    )
    (asserts! (default-to false (map-get? regulatory-staff tx-sender)) err-not-authorized)
    (ok (map-set expedited-reports report-id
      (merge report { status: new-status })
    ))
  )
)

;; Read-Only Functions
(define-read-only (get-event-details (event-id uint))
  (ok (map-get? serious-adverse-events event-id))
)

(define-read-only (get-causality-assessment (assessment-id uint))
  (ok (map-get? causality-assessments assessment-id))
)

(define-read-only (get-report-info (report-id uint))
  (ok (map-get? expedited-reports report-id))
)

(define-read-only (get-notification-info (notification-id uint))
  (ok (map-get? sponsor-notifications notification-id))
)

(define-read-only (get-submission-info (submission-id uint))
  (ok (map-get? regulatory-submissions submission-id))
)

(define-read-only (get-event-reports (event-id uint))
  (ok (map-get? event-reports event-id))
)

(define-read-only (get-site-statistics (site-id (string-ascii 50)))
  (ok (map-get? site-stats site-id))
)

(define-read-only (is-site-coordinator (address principal))
  (ok (default-to false (map-get? site-coordinators address)))
)

(define-read-only (is-medical-reviewer (address principal))
  (ok (default-to false (map-get? medical-reviewers address)))
)

(define-read-only (is-regulatory-staff (address principal))
  (ok (default-to false (map-get? regulatory-staff address)))
)

(define-read-only (is-sponsor (address principal))
  (ok (default-to false (map-get? sponsors address)))
)

(define-read-only (get-event-count)
  (ok (var-get event-nonce))
)

(define-read-only (get-assessment-count)
  (ok (var-get assessment-nonce))
)

(define-read-only (get-report-count)
  (ok (var-get report-nonce))
)

(define-read-only (get-notification-count)
  (ok (var-get notification-nonce))
)

(define-read-only (get-submission-count)
  (ok (var-get submission-nonce))
)

(define-read-only (check-deadline-status (report-id uint))
  (let
    (
      (report (unwrap! (map-get? expedited-reports report-id) err-report-not-found))
    )
    (ok {
      overdue: (> block-height (get submission-deadline report)),
      blocks-remaining: (if (> (get submission-deadline report) block-height)
        (- (get submission-deadline report) block-height)
        u0
      ),
      submitted: (get submitted report)
    })
  )
)

(define-read-only (get-contract-owner)
  (ok contract-owner)
)


;; title: serious-event-reporter
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

