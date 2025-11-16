;; Clinical Trial Serious Adverse Event Reporting
;; Research safety platform for identifying serious events and coordinating expedited reporting

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-not-authorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-already-assessed (err u105))
(define-constant err-already-submitted (err u106))
(define-constant err-deadline-passed (err u107))
(define-constant err-invalid-severity (err u108))

;; Reporting deadlines in blocks (approximating days)
(define-constant expedited-deadline-fatal u1008) ;; ~7 days
(define-constant expedited-deadline-serious u2160) ;; ~15 days

;; Data Variables
(define-data-var sae-nonce uint u0)
(define-data-var assessment-nonce uint u0)
(define-data-var submission-nonce uint u0)
(define-data-var study-nonce uint u0)
(define-data-var total-saes uint u0)

;; Data Maps
(define-map clinical-studies
    { study-id: uint }
    {
        protocol-number: (string-ascii 50),
        sponsor: principal,
        principal-investigator: principal,
        study-phase: (string-ascii 20),
        registration-block: uint,
        active: bool,
        total-events: uint
    }
)

(define-map serious-adverse-events
    { event-id: uint }
    {
        study-id: uint,
        patient-identifier: (string-ascii 50),
        reporter: principal,
        event-description: (string-ascii 500),
        severity-grade: (string-ascii 30),
        onset-block: uint,
        detection-block: uint,
        outcome: (string-ascii 50),
        hospitalization-required: bool,
        life-threatening: bool,
        resulted-in-death: bool,
        status: (string-ascii 20),
        requires-expedited: bool
    }
)

(define-map causality-assessments
    { assessment-id: uint }
    {
        event-id: uint,
        assessor: principal,
        relationship: (string-ascii 30),
        assessment-rationale: (string-ascii 500),
        assessment-block: uint,
        certainty-level: (string-ascii 20)
    }
)

(define-map sponsor-notifications
    { notification-id: uint }
    {
        event-id: uint,
        notification-block: uint,
        acknowledged: bool,
        acknowledgment-block: uint,
        acknowledged-by: (optional principal)
    }
)

(define-map regulatory-submissions
    { submission-id: uint }
    {
        event-id: uint,
        submitter: principal,
        regulatory-authority: (string-ascii 50),
        submission-type: (string-ascii 50),
        submission-block: uint,
        deadline-block: uint,
        status: (string-ascii 20),
        reference-number: (string-ascii 100)
    }
)

(define-map investigator-authorizations
    { study-id: uint, investigator: principal }
    { authorized: bool, authorization-block: uint }
)

(define-map event-timeline
    { event-id: uint, sequence: uint }
    {
        action-type: (string-ascii 50),
        action-by: principal,
        action-block: uint,
        notes: (string-ascii 200)
    }
)

(define-map safety-signals
    { study-id: uint, event-type: (string-ascii 100) }
    {
        occurrence-count: uint,
        last-occurrence-block: uint,
        flagged: bool
    }
)

;; Private Functions
(define-private (calculate-deadline (event-severity (string-ascii 30)) (detection-block uint))
    (if (or (is-eq event-severity "fatal") (is-eq event-severity "death"))
        (+ detection-block expedited-deadline-fatal)
        (+ detection-block expedited-deadline-serious)
    )
)

(define-private (is-expedited-required (life-threatening bool) (death bool) (severity (string-ascii 30)))
    (or life-threatening death 
        (or (is-eq severity "fatal") (is-eq severity "death"))
    )
)

;; Public Functions

;; Register a clinical study
(define-public (register-study
    (protocol-number (string-ascii 50))
    (principal-investigator principal)
    (study-phase (string-ascii 20)))
    (let
        (
            (study-id (var-get study-nonce))
            (sponsor tx-sender)
        )
        (map-set clinical-studies
            { study-id: study-id }
            {
                protocol-number: protocol-number,
                sponsor: sponsor,
                principal-investigator: principal-investigator,
                study-phase: study-phase,
                registration-block: block-height,
                active: true,
                total-events: u0
            }
        )
        (map-set investigator-authorizations
            { study-id: study-id, investigator: principal-investigator }
            { authorized: true, authorization-block: block-height }
        )
        (var-set study-nonce (+ study-id u1))
        (ok study-id)
    )
)

;; Authorize additional investigators
(define-public (authorize-investigator (study-id uint) (investigator principal))
    (let
        (
            (study (unwrap! (map-get? clinical-studies { study-id: study-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender (get sponsor study)) err-not-authorized)
        (map-set investigator-authorizations
            { study-id: study-id, investigator: investigator }
            { authorized: true, authorization-block: block-height }
        )
        (ok true)
    )
)

;; Report a serious adverse event
(define-public (report-sae
    (study-id uint)
    (patient-identifier (string-ascii 50))
    (event-description (string-ascii 500))
    (severity-grade (string-ascii 30))
    (onset-block uint)
    (outcome (string-ascii 50))
    (hospitalization-required bool)
    (life-threatening bool)
    (resulted-in-death bool))
    (let
        (
            (event-id (var-get sae-nonce))
            (study (unwrap! (map-get? clinical-studies { study-id: study-id }) err-not-found))
            (auth (unwrap! (map-get? investigator-authorizations 
                { study-id: study-id, investigator: tx-sender }) err-not-authorized))
            (expedited (is-expedited-required life-threatening resulted-in-death severity-grade))
        )
        (asserts! (get authorized auth) err-not-authorized)
        (asserts! (get active study) err-invalid-status)
        
        ;; Record the SAE
        (map-set serious-adverse-events
            { event-id: event-id }
            {
                study-id: study-id,
                patient-identifier: patient-identifier,
                reporter: tx-sender,
                event-description: event-description,
                severity-grade: severity-grade,
                onset-block: onset-block,
                detection-block: block-height,
                outcome: outcome,
                hospitalization-required: hospitalization-required,
                life-threatening: life-threatening,
                resulted-in-death: resulted-in-death,
                status: "reported",
                requires-expedited: expedited
            }
        )
        
        ;; Update study event count
        (map-set clinical-studies
            { study-id: study-id }
            (merge study { total-events: (+ (get total-events study) u1) })
        )
        
        ;; Update global count
        (var-set total-saes (+ (var-get total-saes) u1))
        (var-set sae-nonce (+ event-id u1))
        
        ;; Record timeline entry
        (map-set event-timeline
            { event-id: event-id, sequence: u0 }
            {
                action-type: "sae-reported",
                action-by: tx-sender,
                action-block: block-height,
                notes: "Initial SAE report submitted"
            }
        )
        
        (ok event-id)
    )
)

;; Assess causality
(define-public (assess-causality
    (event-id uint)
    (relationship (string-ascii 30))
    (assessment-rationale (string-ascii 500))
    (certainty-level (string-ascii 20)))
    (let
        (
            (assessment-id (var-get assessment-nonce))
            (event (unwrap! (map-get? serious-adverse-events { event-id: event-id }) err-not-found))
            (study (unwrap! (map-get? clinical-studies { study-id: (get study-id event) }) err-not-found))
            (auth (unwrap! (map-get? investigator-authorizations 
                { study-id: (get study-id event), investigator: tx-sender }) err-not-authorized))
        )
        (asserts! (get authorized auth) err-not-authorized)
        
        (map-set causality-assessments
            { assessment-id: assessment-id }
            {
                event-id: event-id,
                assessor: tx-sender,
                relationship: relationship,
                assessment-rationale: assessment-rationale,
                assessment-block: block-height,
                certainty-level: certainty-level
            }
        )
        
        ;; Update event status
        (map-set serious-adverse-events
            { event-id: event-id }
            (merge event { status: "assessed" })
        )
        
        ;; Record timeline
        (map-set event-timeline
            { event-id: event-id, sequence: u1 }
            {
                action-type: "causality-assessed",
                action-by: tx-sender,
                action-block: block-height,
                notes: "Causality assessment completed"
            }
        )
        
        (var-set assessment-nonce (+ assessment-id u1))
        (ok assessment-id)
    )
)

;; Notify sponsor
(define-public (notify-sponsor (event-id uint))
    (let
        (
            (event (unwrap! (map-get? serious-adverse-events { event-id: event-id }) err-not-found))
            (study (unwrap! (map-get? clinical-studies { study-id: (get study-id event) }) err-not-found))
            (notification-id (+ event-id u1000000)) ;; Simple unique ID
        )
        (asserts! (is-eq tx-sender (get reporter event)) err-not-authorized)
        
        (map-set sponsor-notifications
            { notification-id: notification-id }
            {
                event-id: event-id,
                notification-block: block-height,
                acknowledged: false,
                acknowledgment-block: u0,
                acknowledged-by: none
            }
        )
        
        ;; Record timeline
        (map-set event-timeline
            { event-id: event-id, sequence: u2 }
            {
                action-type: "sponsor-notified",
                action-by: tx-sender,
                action-block: block-height,
                notes: "Sponsor notification sent"
            }
        )
        
        (ok notification-id)
    )
)

;; Acknowledge sponsor notification
(define-public (acknowledge-notification (notification-id uint))
    (let
        (
            (notification (unwrap! (map-get? sponsor-notifications { notification-id: notification-id }) err-not-found))
            (event (unwrap! (map-get? serious-adverse-events { event-id: (get event-id notification) }) err-not-found))
            (study (unwrap! (map-get? clinical-studies { study-id: (get study-id event) }) err-not-found))
        )
        (asserts! (is-eq tx-sender (get sponsor study)) err-not-authorized)
        (asserts! (not (get acknowledged notification)) err-already-exists)
        
        (map-set sponsor-notifications
            { notification-id: notification-id }
            (merge notification {
                acknowledged: true,
                acknowledgment-block: block-height,
                acknowledged-by: (some tx-sender)
            })
        )
        (ok true)
    )
)

;; Submit to regulatory authority
(define-public (submit-to-authority
    (event-id uint)
    (regulatory-authority (string-ascii 50))
    (submission-type (string-ascii 50))
    (reference-number (string-ascii 100)))
    (let
        (
            (submission-id (var-get submission-nonce))
            (event (unwrap! (map-get? serious-adverse-events { event-id: event-id }) err-not-found))
            (study (unwrap! (map-get? clinical-studies { study-id: (get study-id event) }) err-not-found))
            (deadline (calculate-deadline (get severity-grade event) (get detection-block event)))
        )
        (asserts! (is-eq tx-sender (get sponsor study)) err-not-authorized)
        
        (map-set regulatory-submissions
            { submission-id: submission-id }
            {
                event-id: event-id,
                submitter: tx-sender,
                regulatory-authority: regulatory-authority,
                submission-type: submission-type,
                submission-block: block-height,
                deadline-block: deadline,
                status: "submitted",
                reference-number: reference-number
            }
        )
        
        ;; Update event status
        (map-set serious-adverse-events
            { event-id: event-id }
            (merge event { status: "submitted" })
        )
        
        ;; Record timeline
        (map-set event-timeline
            { event-id: event-id, sequence: u3 }
            {
                action-type: "regulatory-submission",
                action-by: tx-sender,
                action-block: block-height,
                notes: "Submitted to regulatory authority"
            }
        )
        
        (var-set submission-nonce (+ submission-id u1))
        (ok submission-id)
    )
)

;; Update submission status
(define-public (update-submission-status (submission-id uint) (new-status (string-ascii 20)))
    (let
        (
            (submission (unwrap! (map-get? regulatory-submissions { submission-id: submission-id }) err-not-found))
            (event (unwrap! (map-get? serious-adverse-events { event-id: (get event-id submission) }) err-not-found))
            (study (unwrap! (map-get? clinical-studies { study-id: (get study-id event) }) err-not-found))
        )
        (asserts! (is-eq tx-sender (get sponsor study)) err-not-authorized)
        
        (map-set regulatory-submissions
            { submission-id: submission-id }
            (merge submission { status: new-status })
        )
        (ok true)
    )
)

;; Update event outcome
(define-public (update-event-outcome (event-id uint) (new-outcome (string-ascii 50)))
    (let
        (
            (event (unwrap! (map-get? serious-adverse-events { event-id: event-id }) err-not-found))
            (auth (unwrap! (map-get? investigator-authorizations 
                { study-id: (get study-id event), investigator: tx-sender }) err-not-authorized))
        )
        (asserts! (get authorized auth) err-not-authorized)
        
        (map-set serious-adverse-events
            { event-id: event-id }
            (merge event { outcome: new-outcome })
        )
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-study (study-id uint))
    (map-get? clinical-studies { study-id: study-id })
)

(define-read-only (get-sae (event-id uint))
    (map-get? serious-adverse-events { event-id: event-id })
)

(define-read-only (get-causality-assessment (assessment-id uint))
    (map-get? causality-assessments { assessment-id: assessment-id })
)

(define-read-only (get-notification (notification-id uint))
    (map-get? sponsor-notifications { notification-id: notification-id })
)

(define-read-only (get-submission (submission-id uint))
    (map-get? regulatory-submissions { submission-id: submission-id })
)

(define-read-only (get-timeline-entry (event-id uint) (sequence uint))
    (map-get? event-timeline { event-id: event-id, sequence: sequence })
)

(define-read-only (is-investigator-authorized (study-id uint) (investigator principal))
    (match (map-get? investigator-authorizations { study-id: study-id, investigator: investigator })
        auth (get authorized auth)
        false
    )
)

(define-read-only (get-total-saes)
    (ok (var-get total-saes))
)

(define-read-only (check-deadline-status (event-id uint))
    (match (map-get? serious-adverse-events { event-id: event-id })
        event
        (let
            (
                (deadline (calculate-deadline (get severity-grade event) (get detection-block event)))
            )
            (ok {
                deadline: deadline,
                current-block: block-height,
                overdue: (> block-height deadline),
                blocks-remaining: (if (> deadline block-height) (- deadline block-height) u0)
            })
        )
        err-not-found
    )
)

